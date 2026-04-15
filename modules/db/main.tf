# * the database with replication

# TOFIX
# resource "aws_dynamodb_global_secondary_index" "web_server" { # OK
#   table_name = aws_dynamodb_table.web_server.name
#   index_name = "GameTitleIndex"

#   projection {
#     projection_type    = "INCLUDE"
#     non_key_attributes = ["UserId"]
#   }

#   provisioned_throughput {
#     write_capacity_units = 10
#     read_capacity_units  = 10
#   }

#   key_schema {
#     attribute_name = "GameTitle"
#     attribute_type = "S"
#     key_type       = "HASH"
#   }
# }

resource "aws_dynamodb_table" "web_server" { # OK
  name           = "web_server"
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "UserId"
  range_key      = "GameTitle"

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "UserId"
    type = "S"
  }

  attribute {
    name = "GameTitle"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.adminaccount_web_key_arn
  }
}

# * autoscaling

resource "aws_appautoscaling_target" "web_server" { # OK
  resource_id        = "table/${aws_dynamodb_table.web_server.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits" # read units
  service_namespace  = "dynamodb"
  min_capacity       = 1
  max_capacity       = 15
}

# https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/AutoScaling.html
# UpdateTable request to adjust throughput
# Table metrics + cloudwatch alarms and receive on sns
resource "aws_appautoscaling_policy" "web_server" { # OK
  name               = "web_server"
  service_namespace  = aws_appautoscaling_target.web_server.service_namespace
  scalable_dimension = aws_appautoscaling_target.web_server.scalable_dimension
  resource_id        = aws_appautoscaling_target.web_server.resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {

    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }

    target_value = 70 # adjust wcu/rcu to maintain at 70% (consumed vs provisioned)

  }


}
