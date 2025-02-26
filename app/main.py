from flask import Flask
import boto3
import os
import logging
import time
import botocore.exceptions
import requests
from botocore.config import Config

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')

def check_metadata_service():
    try:
        response = requests.get('http://169.254.170.2/latest/meta-data/iam/security-credentials/', timeout=2)
        if response.status_code == 200:
            logger.info(f"Metadata service accessible, credentials: {response.text}")
            return True
        logger.error(f"Metadata service failed: {response.status_code}, {response.text}")
        return False
    except Exception as e:
        logger.error(f"Metadata service unreachable: {str(e)}")
        return False

def get_dynamodb():
    max_retries = 15  # Increase retries significantly
    retry_delay = 10  # Longer delay between retries (in seconds)
    for attempt in range(max_retries):
        try:
            logger.info(f"Attempting to fetch AWS credentials (attempt {attempt + 1}/{max_retries})")
            if not check_metadata_service():
                logger.error("Metadata service check failed—skipping attempt")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                continue

            # Use a custom botocore config for more retries
            boto_config = Config(
                retries={'max_attempts': 10, 'mode': 'standard'},
                connect_timeout=5,
                read_timeout=10
            )
            sts_client = boto3.client('sts', region_name=AWS_REGION, config=boto_config)
            identity = sts_client.get_caller_identity()
            logger.info(f"Credentials found: {identity}")
            return boto3.resource('dynamodb', region_name=AWS_REGION, config=boto_config)
        except botocore.exceptions.ClientError as e:
            if e.response['Error']['Code'] == 'UnauthorizedOperation':
                logger.error(f"Unauthorized operation: {str(e)}")
            elif e.response['Error']['Code'] == 'AccessDenied':
                logger.error(f"Access denied: {str(e)}")
            else:
                logger.error(f"Failed to fetch credentials: {str(e)}")
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
            else:
                raise
        except Exception as e:
            logger.error(f"Unexpected error fetching credentials: {str(e)}")
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
            else:
                raise
    raise Exception("Max retries reached for credentials")

dynamodb = get_dynamodb()
table = dynamodb.Table('DemoHits')

@app.route("/")
def index():
    try:
        logger.info("Attempting to update DynamoDB hit counter")
        response = table.update_item(
            Key={'id': 'hit_counter'},
            UpdateExpression="SET hit_count = if_not_exists(hit_count, :start) + :inc",
            ExpressionAttributeValues={':start': 0, ':inc': 1},
            ReturnValues="UPDATED_NEW"
        )
        count = response['Attributes']['hit_count']
        logger.info(f"Successfully updated counter to {count}")
        return f"Welcome to my AWS DevOps Demo! Page Hits: {int(count)}"
    except Exception as e:
        logger.error(f"Error accessing DynamoDB: {str(e)}")
        return f"Error accessing DynamoDB: {str(e)}", 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
    