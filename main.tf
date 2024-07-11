terraform {

  cloud {
    organization = "chrisnieves60" #change to your organization

    workspaces {
      name = "learn-terraform-github-actions2" #change to your workspace name
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  required_version = ">= 0.14.0"
}


variable "region" {
  description = "AWS region to deploy resources to"
  type        = string
  default     = "us-west-2"
}
variable "key_pair_name" {
  description = "key pair name"
  type        = string
}
variable "availability_zone" {
  description = "AWS region to deploy resources to (availability)"
  type        = string
  default     = "us-west-2a"
}
variable "tag_name" {
  description = "tag name"
  type        = string
}
variable "ami_id" {
  description = "Amazon Machine Image ID"
  type        = string
}
provider "aws" {
  region = var.region
}

# Create VPC
resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = var.tag_name
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = var.tag_name
  }
}

# Create Subnet
resource "aws_subnet" "my_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = var.tag_name
  }
}

# Create Route Table
resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = var.tag_name
  }
}

# Associate Subnet with Route Table
resource "aws_route_table_association" "my_route_association" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.my_route_table.id
}

# Allow HTTP (port 80), HTTPS (port 443), and SSH (port 22) traffic
resource "aws_security_group" "my_security_group" {
  vpc_id = aws_vpc.my_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["18.237.140.160/29"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["207.225.223.16/32"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["98.113.250.244/32"] #Change to your IP
  }

  tags = {
    Name = var.tag_name
  }
}

#SSM role for ec2 instance
resource "aws_iam_role" "ssm_role" {
  name = "ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_role_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "ssm_instance_profile"
  role = aws_iam_role.ssm_role.name
}

# Launch EC2 instance
resource "aws_instance" "openemr_instance" {
  ami                    = var.ami_id
  instance_type          = "t2.micro"
  iam_instance_profile   = aws_iam_instance_profile.ssm_instance_profile.name
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.my_subnet.id
  vpc_security_group_ids = [aws_security_group.my_security_group.id]

  user_data = file("${path.module}/user_data.sh")

  tags = {
    Name       = var.tag_name
    Enviroment = "Testing"
  }
}

# Allocate an Elastic IP
resource "aws_eip" "my_eip" {
}

# Associate the Elastic IP with the instance
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.openemr_instance.id
  allocation_id = aws_eip.my_eip.id
}

#LAMBDA EXEC ROLE 
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}
#SQS QUEUE
resource "aws_sqs_queue" "procedure_queue" {
  name                        = "procedure_queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 30
}

#INLINE IAM POLICY, ATTACHING TO LAMBDA_EXEC ROLE 
resource "aws_iam_role_policy" "lambda_sqs_role_policy" {
  name = "lambda_sqs_policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ssm:SendCommand"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ssm:ListCommandInvocations"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ],
        Resource = "${aws_sqs_queue.procedure_queue.arn}"
      }
    ]
  })
}


resource "aws_lambda_function" "InsertionScript" {
  function_name = "InsertionScript"
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.8"
  role          = aws_iam_role.lambda_exec.arn
  filename      = "lambda_function_payload.zip"
  timeout       = 30

  source_code_hash = filebase64sha256("lambda_function_payload.zip")
}


#API IAM ROLE 
resource "aws_iam_role" "apigateway_sqs_role" {
  name = "apigateway_sqs_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}
resource "aws_iam_role_policy" "apigateway_sqs_policy" {
  name = "apigateway_sqs_policy"
  role = aws_iam_role.apigateway_sqs_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "sqs:SendMessage",
        Resource = "${aws_sqs_queue.procedure_queue.arn}"
      }
    ]
  })
}

#API GATEWAY CREATION
resource "aws_api_gateway_rest_api" "InsertApi" {
  name        = "InsertApi"
  description = "Insert procedure or order via api call"
}
resource "aws_api_gateway_resource" "order_resource" {
  rest_api_id = aws_api_gateway_rest_api.InsertApi.id
  parent_id   = aws_api_gateway_rest_api.InsertApi.root_resource_id
  path_part   = "order"
}
resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.InsertApi.id
  resource_id   = aws_api_gateway_resource.order_resource.id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration_response" "sqs_integration_response_default" {
  rest_api_id = aws_api_gateway_rest_api.InsertApi.id
  resource_id = aws_api_gateway_resource.order_resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = "200"

  # This will catch all responses that don't match other integration responses
  selection_pattern = ""

  response_templates = {
    "application/json" = <<EOF
    #set($inputRoot = $input.path('$'))
    {
      "response": $inputRoot
    }
    EOF
  }

  depends_on = [aws_api_gateway_integration.sqs_integration]
}
resource "aws_api_gateway_integration" "sqs_integration" {
  rest_api_id             = aws_api_gateway_rest_api.InsertApi.id
  resource_id             = aws_api_gateway_resource.order_resource.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.region}:sqs:path/${aws_sqs_queue.procedure_queue.name}"
  credentials             = aws_iam_role.apigateway_sqs_role.arn
  request_parameters = {
    "integration.request.querystring.Version" = "'2012-11-05'"
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }
  request_templates = {
    "application/json" = <<-EOF
  Action=SendMessage&Version=2012-11-05&MessageBody=$input.body&QueueUrl=${aws_sqs_queue.procedure_queue.id}&MessageGroupId=default
  EOF
  }
  passthrough_behavior = "WHEN_NO_TEMPLATES"
}

# API Gateway Method Response
resource "aws_api_gateway_integration_response" "sqs_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.InsertApi.id
  resource_id = aws_api_gateway_resource.order_resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = "200"

  selection_pattern = "2\\d{2}"

  response_templates = {
    "application/json" = <<EOF
{
  "message": "Message sent to SQS successfully",
  "messageId": $input.json('$.MessageId')
}
EOF
  }

  depends_on = [aws_api_gateway_integration.sqs_integration]
}
resource "aws_api_gateway_integration_response" "sqs_integration_response_error" {
  rest_api_id = aws_api_gateway_rest_api.InsertApi.id
  resource_id = aws_api_gateway_resource.order_resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = "400"

  selection_pattern = "4\\d{2}" # Regex for 4XX status codes

  response_templates = {
    "application/json" = <<EOF
{
  "message": "Error sending message to SQS",
  "error": $input.json('$.Error.Message')
}
EOF
  }

  depends_on = [aws_api_gateway_integration.sqs_integration]
}
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.InsertApi.id
  resource_id = aws_api_gateway_resource.order_resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}
resource "aws_api_gateway_method_response" "response_400" {
  rest_api_id = aws_api_gateway_rest_api.InsertApi.id
  resource_id = aws_api_gateway_resource.order_resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = "400"

  response_models = {
    "application/json" = "Error"
  }
  response_parameters = {
    "method.response.header.Content-Type" = true
  }
}



resource "aws_api_gateway_deployment" "InsertionDeployment" {
  rest_api_id = aws_api_gateway_rest_api.InsertApi.id
  stage_name  = "dev"

  depends_on = [
    aws_api_gateway_integration.sqs_integration,
    aws_api_gateway_integration_response.sqs_integration_response,
    aws_api_gateway_integration_response.sqs_integration_response_error,
    aws_api_gateway_integration_response.sqs_integration_response_default
  ]
}
resource "aws_lambda_event_source_mapping" "map_sqs_to_lamdba" {
  event_source_arn = aws_sqs_queue.procedure_queue.arn
  function_name    = aws_lambda_function.InsertionScript.arn
}
resource "aws_lambda_permission" "sqs_invoke_lambda" {
  statement_id  = "AllowSQSToInvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.InsertionScript.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = aws_sqs_queue.procedure_queue.arn
}

