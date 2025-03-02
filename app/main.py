from flask import Flask
import boto3
import os
import logging
import time
from botocore.exceptions import ClientError

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')

def get_dynamodb():
    max_retries = 15
    retry_delay = 2
    
    for attempt in range(max_retries):
        try:
            logger.info(f"Attempt {attempt+1}/{max_retries} to connect to DynamoDB")
            dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
            logger.info("DynamoDB connection assumed successful")
            return dynamodb
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', '')
            error_msg = e.response.get('Error', {}).get('Message', str(e))
            logger.error(f"DynamoDB client error: {error_code} - {error_msg}")
            if error_code in ['AccessDenied', 'UnauthorizedOperation']:
                logger.error("Permissions issue detected")
            if attempt < max_retries - 1:
                logger.info(f"Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                logger.error("Max retries reached for DynamoDB connection")
                raise
        except Exception as e:
            logger.error(f"Unexpected error connecting to DynamoDB: {str(e)}")
            if attempt < max_retries - 1:
                logger.info(f"Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                logger.error("Max retries reached for DynamoDB connection")
                raise

try:
    dynamodb = get_dynamodb()
    table = dynamodb.Table('DemoHits')
    logger.info("DynamoDB connection initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize DynamoDB: {str(e)}")
    dynamodb = None
    table = None

@app.route("/")
def index():
    global dynamodb, table
    if table is None:
        try:
            logger.info("Attempting to reinitialize DynamoDB connection")
            dynamodb = get_dynamodb()
            table = dynamodb.Table('DemoHits')
            logger.info("DynamoDB connection reinitialized successfully")
        except Exception as e:
            logger.error(f"Failed to reinitialize DynamoDB: {str(e)}")
            return "Application experiencing database connectivity issues. Please try again later.", 500
    try:
        logger.info("Updating DynamoDB hit counter")
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
        logger.error(f"Error updating hit counter: {str(e)}")
        return "Application experiencing database connectivity issues. Please try again later.", 500

@app.route("/health")
def health():
    logger.info("Health check passed with status 200")
    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
    