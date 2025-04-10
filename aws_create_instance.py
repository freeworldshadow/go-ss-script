import boto3
import botocore.exceptions
from datetime import datetime
import time

# 预定义的区域与 Ubuntu 22.04 Server (amd64, HVM, EBS gp2) AMI ID 对照表
UBUNTU_AMI_MAPPING = {
    'us-east-1': 'ami-0a13e2564b4c1f58a',
    'us-east-2': 'ami-0b2e2a9fd5b85c819',
    'us-west-1': 'ami-0c76a5a9e3f8a6f71',
    'us-west-2': 'ami-0b5df5ed1e3bfc9a3',
    'eu-west-1': 'ami-0b8d1dcbdaf2b1e4c',
    'eu-central-1': 'ami-0b1cf19c6e631b9a3',
    'ap-southeast-1': 'ami-09aa15d321b39a2f4',
    'ap-southeast-2': 'ami-0e3b0fad204d7f7a1',
    'ap-northeast-1': 'ami-0e78a27a6c0b2a8a1',
    'ap-northeast-2': 'ami-0c9d0ec2ae8e74bcf',
    'sa-east-1': 'ami-0cba12f5ff23a7c97',
    'ca-central-1': 'ami-02e76f23347b8e87f'
}

def get_ubuntu_ami_from_mapping(region):
    """
    根据传入的区域代码，从预定义对照表中获取 Ubuntu 22.04 Server 的 AMI ID
    """
    ami_id = UBUNTU_AMI_MAPPING.get(region)
    if ami_id:
        print(f"[INFO] 使用静态对照表，在区域 {region} 获取的 Ubuntu 22.04 AMI ID: {ami_id}")
    else:
        print(f"[ERROR] 区域 {region} 未配置对应的 Ubuntu 22.04 AMI ID！")
    return ami_id

def get_or_create_security_group(ec2_client, vpc_id):
    """
    自动生成安全组名称，格式为：lanst-sg-(timestamp)
    并检查是否已存在同名安全组，如果存在则返回它，
    否则新建一个安全组并设置全放行规则（入站、出站全部允许）。
    """
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    group_name = f"lanst-sg-{timestamp}"

    # 尝试查找同名安全组（在同一 VPC 内安全组名称唯一，通常不会重复）
    try:
        response = ec2_client.describe_security_groups(
            Filters=[{'Name': 'group-name', 'Values': [group_name]}]
        )
        if response['SecurityGroups']:
            sg_id = response['SecurityGroups'][0]['GroupId']
            print(f"[INFO] 找到现有安全组 {group_name}，ID: {sg_id}")
            return sg_id
    except botocore.exceptions.ClientError as e:
        print(f"[WARN] 检查安全组时出错: {e}")

    try:
        # 创建新的安全组
        response = ec2_client.create_security_group(
            GroupName=group_name,
            Description='Security group with all ports open',
            VpcId=vpc_id
        )
        sg_id = response['GroupId']
        print(f"[INFO] 创建新的安全组 {group_name}，ID: {sg_id}")

        # 添加入站规则：开放所有流量
        ec2_client.authorize_security_group_ingress(
            GroupId=sg_id,
            IpPermissions=[
                {
                    'IpProtocol': '-1',  # 所有协议
                    'FromPort': 0,
                    'ToPort': 65535,
                    'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
                }
            ]
        )

        # 添加入站规则成功后添加出站规则
        try:
            ec2_client.authorize_security_group_egress(
                GroupId=sg_id,
                IpPermissions=[
                    {
                        'IpProtocol': '-1',  # 所有协议
                        'FromPort': 0,
                        'ToPort': 65535,
                        'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
                    }
                ]
            )
        except botocore.exceptions.ClientError as e:
            # 如果是重复规则错误，则忽略
            if "InvalidPermission.Duplicate" in str(e):
                print("[WARN] 安全组出站规则已存在，跳过添加出站规则。")
            else:
                print(f"[ERROR] 添加安全组出站规则时出错: {e}")
                return None

        return sg_id
    except botocore.exceptions.ClientError as e:
        print(f"[ERROR] 创建安全组时出错: {e}")
        return None

def create_ec2_instance(instance_type, region, access_key, secret_key):
    """
    创建 EC2 实例：
      - 参数 instance_type 如 't3.micro'
      - 参数 region 如 'us-west-1'
      - 使用 access_key 和 secret_key 初始化 boto3 客户端
      - 根据区域代码获取对照表中的最新 Ubuntu 22.04 Server AMI ID
      - 安全组由自动生成的 lanst-sg-(timestamp) 安全组
      - UserData 为启动后自动执行远程脚本安装 Shadowsocks
    """
    # 初始化 EC2 client
    ec2_client = boto3.client(
        'ec2',
        region_name=region,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key
    )

    # 从对照表中获取 Ubuntu 22.04 AMI ID
    ami_id = get_ubuntu_ami_from_mapping(region)
    if not ami_id:
        print("[ERROR] 无法获取 AMI ID，终止实例创建。")
        return

    # 获取默认 VPC ID
    try:
        vpcs = ec2_client.describe_vpcs()
        vpc_id = vpcs['Vpcs'][0]['VpcId']
        print(f"[INFO] 默认 VPC ID: {vpc_id}")
    except botocore.exceptions.ClientError as e:
        print(f"[ERROR] 获取默认 VPC ID 时出错: {e}")
        return

    # 获取或创建安全组
    sg_id = get_or_create_security_group(ec2_client, vpc_id)
    if not sg_id:
        print("[ERROR] 无法获取或创建安全组，终止实例创建。")
        return

    # UserData 脚本：开机后自动执行远程安装 Shadowsocks 的脚本
    user_data_script = '''#!/bin/bash
curl -O https://raw.githubusercontent.com/freeworldshadow/go-ss-script/refs/heads/main/install_shadowsocks.sh && \
chmod +x install_shadowsocks.sh && \
sudo ./install_shadowsocks.sh
'''

    try:
        response = ec2_client.run_instances(
            ImageId=ami_id,
            InstanceType=instance_type,
            MinCount=1,
            MaxCount=1,
            SecurityGroupIds=[sg_id],
            TagSpecifications=[{
                'ResourceType': 'instance',
                'Tags': [{'Key': 'Name', 'Value': 'MyUbuntuServer'}]
            }],
            UserData=user_data_script
        )
        instance_id = response['Instances'][0]['InstanceId']
        print(f"[INFO] 成功创建 EC2 实例，ID: {instance_id}")
    except botocore.exceptions.ClientError as e:
        print(f"[ERROR] 创建 EC2 实例时出错: {e}")
        return

    # 利用 boto3 resource 等待实例进入 running 状态，并获取公开 IP 地址
    ec2_resource = boto3.resource(
        'ec2',
        region_name=region,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key
    )
    instance = ec2_resource.Instance(instance_id)
    
    print("[INFO] 等待实例进入 running 状态...")
    instance.wait_until_running()
    
    # 刷新实例状态信息
    instance.load()
    public_ip = instance.public_ip_address
    print(f"[INFO] 实例 {instance_id} 公开 IP 地址为: {public_ip}")
    return {"instance_id": instance_id, "public_ip": public_ip,"region": region,"access_key": access_key,"secret_key": secret_key}


# 示例调用
if __name__ == "__main__":
    
    # 示例：创建 t2.micro 类型的实例，位于 us-west-1 区域，
    # 创建成功后返回实例ID与实例公开 IP 地址
    instance_info = create_ec2_instance('t2.micro', 'us-west-1', '', '')
    if instance_info:
        instance_id = instance_info.get("instance_id")
        public_ip = instance_info.get("public_ip")
        print(f"\n最终结果 -> 实例ID: {instance_id}, 实例公开 IP: {public_ip}")
