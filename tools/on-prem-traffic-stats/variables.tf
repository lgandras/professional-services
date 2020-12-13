/**
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

variable "vpc_project_id" {
    default = "bigorg-hub-prod-prj-e126d530"
}

variable "logs_project_id" {
    default = "bigorg-vpc-flowlogs-a6b76d26"
}

variable "on_prem_ip_range" {
    default = "10.0.0.0/24"
}

variable "dataset_name" {
    default = "vpc_flowlogs_dataset"
}
