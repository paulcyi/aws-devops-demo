from flask import Flask
import boto3
import os
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)  # Log to stdout
logger = logging.getLogger(__name__)

dynamodb = boto3.resource('dynamodb', region_name=os.getenv('AWS_REGION', 'us-east-1'))
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
