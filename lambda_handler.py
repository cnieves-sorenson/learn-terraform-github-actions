import boto3
import json

def lambda_handler(event, context):
    print("Received event: " + json.dumps(event))

    for record in event['Records']: 
        body = record['body']
        message = json.loads(body)
        
        operation_type = message.get('operation_type')
        first_name = message.get('first_name')
        last_name = message.get('last_name')
        dob = message.get('dob')
        abnormal = message.get('abnormal')
        result = message.get('result')

    #incorrect body exception response
    if not first_name or not last_name or not dob or not operation_type: 
        return {
            'statusCode': 400, 
            'body': json.dumps('Missing req parameters: first_name, last_name, dob, operation_type, abnormal, result')
        }
    
    # instantiate ssm client
    ssm_client = boto3.client('ssm')
    ec2_client = boto3.client('ec2')

    try: 
        tag_key = 'Name'
        tag_value = 'OpenEMR-Tag'

        response = ec2_client.describe_instances(
            Filters=[
                {
                    'Name': f'tag:{tag_key}', 
                    'Values': [tag_value]
                },
                {
                    'Name': 'instance-state-name', 
                    'Values': ['running']
                }
            ]
        )

        instances = response['Reservations']
        if not instances: 
            return {
                'statusCode': 404, 
                'body': json.dumps('No instances found with specified tag')
            }

        instance_id = instances[0]['Instances'][0]['InstanceId']
        
        #command to run on the ec2 instance
        if operation_type == 'insert_procedure': 
            command = f'sh /scripts/insert_procedure.sh "{first_name}" "{last_name}" "{dob}"'
        elif operation_type == 'insert_result': 
            if not abnormal or not result: 
                return {
                    'statusCode': 400, 
                    'body': json.dumps('Missing req parameters: abnormal, result')
                }
            else: 
                command = f'sh /scripts/insert_result.sh "{first_name}" "{last_name}" "{dob}" "{result}" "{abnormal}"'


        #send command to ec2 instance using ssm run command
        ssm_response = ssm_client.send_command(
            InstanceIds = [instance_id], #target ec2 instance
            DocumentName='AWS-RunShellScript', #ssm doc for running shell script 
            Parameters={'commands': [command]} #Parameters for command 
        )

        return {
            'statusCode': 200, 
            'body': json.dumps(ssm_response, default=str)
        }
    except ssm_client.exceptions.InvalidInstanceId as e: 
        print(f"invalid instance ID error: {str((e))}")
        return {
            'statusCode': 400, 
            'body': json.dumps(f'Invalid instance ID: {str(e)}')
        }
    except Exception as e: 
        print(f"Unhandled exception: {str(e)}")
        return {
            'statusCode': 500, 
            'body': json.dumps(f'Unhandled exception: {(str)}')
        }

