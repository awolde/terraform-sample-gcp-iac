## Demo App

A sample IaC that deploys an app with three web nodes and a backend DB server.

For simplicity, SQL instance is running with public IP. 

**Do not do this is production!!**

## Architecture
![picture](demo-app-arch.png)

## Running
Add your project id at the top of the `main.tf` file.
Also your public ip in `my_ip` variable.

Use a service account that has compute admin role.

`terraform init; terraform plan; terraform apply`

## Testing
`curl http://your_lb_ip/index.php`