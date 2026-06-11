import json
import boto3
import os
import urllib.request

def handler(event, context):
    """
    AWS Lambda function triggered by EventBridge when AWS Config 
    detects a NON_COMPLIANT Security Group.
    """
    ec2 = boto3.client('ec2')
    
    # 1. Extract the Security Group ID from the EventBridge payload
    detail = event.get('detail', {})
    resource_id = detail.get('resourceId')
    
    if not resource_id:
        print("Error: No Resource ID found in the event payload.")
        return
    
    print(f"CRITICAL: Exposed SSH detected on Security Group {resource_id}. Initiating auto-remediation...")
    
    try:
        # 2. Command AWS to immediately revoke the 0.0.0.0/0 Port 22 rule
        ec2.revoke_security_group_ingress(
            GroupId=resource_id,
            IpPermissions=[
                {
                    'IpProtocol': 'tcp',
                    'FromPort': 22,
                    'ToPort': 22,
                    'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
                }
            ]
        )
        print(f"SUCCESS: Port 22 successfully locked down on {resource_id}.")
        
        # 3. Fire a webhook alert to an external system (like Slack)
        slack_url = os.environ.get('SLACK_WEBHOOK_URL')
        if slack_url:
            msg = {
                "text": f"🚨 *Auto-Remediation Triggered!* 🚨\nRemoved exposed SSH (Port 22) from Security Group: `{resource_id}`"
            }
            req = urllib.request.Request(
                slack_url, 
                data=json.dumps(msg).encode('utf-8'), 
                headers={'Content-Type': 'application/json'}
            )
            urllib.request.urlopen(req)
            
    except Exception as e:
        print(f"Failed to remediate Security Group {resource_id}: {str(e)}")
        raise e
        
    return {
        "statusCode": 200, 
        "body": f"Successfully remediated {resource_id}"
    }