from flask import Flask
import boto3
import os
import logging
import time
import botocore.exceptions

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')

def get_dynamodb():
    max_retries = 5  # Increase retries
    for attempt in range(max_retries):
        try:
            logger.info(f"Attempting to fetch AWS credentials (attempt {attempt + 1}/{max_retries})")
            sts_client = boto3.client('sts', region_name=AWS_REGION)
            identity = sts_client.get_caller_identity()
            logger.info(f"Credentials found: {identity}")
            return boto3.resource('dynamodb', region_name=AWS_REGION)
        except botocore.exceptions.ClientError as e:
            if e.response['Error']['Code'] == 'UnauthorizedOperation':
                logger.error(f"Unauthorized operation: {str(e)}")
            else:
                logger.error(f"Failed to fetch credentials: {str(e)}")
            if attempt < max_retries - 1:
                time.sleep(2)  # Wait longer
            else:
                raise
        except Exception as e:
            logger.error(f"Unexpected error fetching credentials: {str(e)}")
            if attempt < max_retries - 1:
                time.sleep(2)
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
    