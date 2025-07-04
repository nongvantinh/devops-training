variable "environment" {
  description = "Environment name"
  type        = string
}

variable "services" {
  description = "List of services for ECR repositories"
  type        = list(string)
  default     = ["web", "proxy", "barista", "kitchen", "counter", "product"]
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}