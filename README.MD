# Instant Minecraft

This is a simple project designed to get you up and running with a Minecraft server on AWS in a few simple clicks. This is also designed so that you can easily spin up, take down, and configure your Minecraft server with as little coding as possible.

**A NOTE ON COSTS**: AWS can be pretty expensive, so with heavy usage and high definition, high bitrate content, you could incur heavy charges. I **highly** recommend doing some calculations and setting [billing alerts](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html) before getting started. There are a few major components to cost with running Minecraft on AWS:
* _S3 storage costs_: This is the cost to persistently store your backups on S3.
* _EC2 running costs_: This is the actual cost to run your Minecraft server.
* _EBS volume costs_: This is the cost of the hard drive space attached to your Minecraft server.

## Getting Started

These instructions will walk you through the entire process of setting up a Minecraft server on AWS. It should be pretty easy to follow from top to bottom. If you run into any problems, please create an issue and let me know.

### Prerequisites
1. You'll need to install docker and docker-compose to run this project. Please see https://docs.docker.com/install/ and https://docs.docker.com/compose/install/ for instructions on installing docker and docker compose on your system. Everything runs in docker containers to avoid any incompatibility issues with your system.
1. You'll need an AWS account with full administrator access. This guide assumes you're running this on your own personal AWS account, and that the AWS credentials you use have no restrictions. See https://aws.amazon.com/premiumsupport/knowledge-center/create-and-activate-aws-account/ for details on creating an AWS account.
1. You'll need your AWS access keys. See https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html for details on getting those from the AWS console.
1. You'll need to know how to clone this project from Github. See https://help.github.com/en/github/creating-cloning-and-archiving-repositories/cloning-a-repository for details.
1. You'll need to know how to use a command line terminal. There are many tutorials out there for doing this, so I'll leave finding one for your system as an exercise for the reader.

### Project Setup

1. Copy the `.env.template` file in the project root directory and name the copy `.env`. This is where your configuration for your Minecraft server infrastructure will go, as well as the credentials you'll need to deploy. Below is a description of each item you'll need to configure. Inside your `.env` file, place the raw text string after the equals sign with no extra spaces.
  * `AWS_ACCESS_KEY_ID`: This is your access key ID from AWS. See _Prequisites_ for instructions on getting this.
  * `AWS_REGION`: This is the AWS region in which your Minecraft server will run. This should be close to where you'll be playing the most from. See [this page](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RegionsAndAvailabilityZones.html) for an overview of possible regions. You must use the lowercase-and-hyphen form of the region, e.g. `us-east-1`.
  * `AWS_SECRET_ACCESS_KEY`: This is your secret access key from AWS. See _Prequisites_ for instructions on getting this.
  * `EBS_ROOT_VOLUME_SIZE`: This is the size of the drive that will be the root volume for your Minecraft server, in gigabytes (GiB). It needs enough space for your world, mods, and any other content you plan to add, plus one backup of the above (used when restoring backups).
  * `EC2_INSTANCE_TYPE`: This is the type and size of the server you'll be running the Minecraft server on. See https://aws.amazon.com/ec2/instance-types/ for details on what types of instances are available. I would recommend something relatively small to start, especially if you're only playing with a few friends. For instance, `t3a.small`, would make a good starting instance type. **WARNING**: This will affect your running cost significantly so make sure to calculate this ahead of time to avoid unwanted billing surprises.
  * `ENVIRONMENT`: This is an arbitrary name for your environment, to avoid conflicts if you decide to deploy multiple Minecraft servers. I suggest a cool name, like _mothra_.
  * `HOSTED_ZONE_ID`: (OPTIONAL) If you would like your Minecraft server to be available on a custom, nice and pretty domain, you will need fill this in. See _(Optional) Configuring DNS_ under the _Deployment_ section below for the steps to set this up.
  * `TERRAFORM_STATE_BUCKET`: This is an S3 bucket you will create that will store the configuration of your Terraform backend. Terraform is the tool that lets us write infrastructure as code and tell AWS what resources to create. Storing the infrastructure state in S3 ensures it doesn't get lost if something happens to your local machine.
1. Create an S3 bucket through the AWS console and set the `TERRAFORM_STATE_BUCKET` environment variable to the name of the bucket. Make sure you create this bucket in the region you specified in the `AWS_REGION` environment variable. Be sure to call it something unique, like _mothra-terraform-state_.
1. Create an ssh key by running `ssh-keygen -b 2048 -t rsa -f ./.ssh/minecraft-key -q -P """"`. This will be used by our Terraform code to provision files on our EC2 instance.

Now you're all set and ready to start deploying!

## Deployment

### (Optional) Configuring DNS

If you want your Minecraft server to be available at a particular domain name (let's say something cool, like `mothra.pictures`), you should also complete these steps. This will host your Minecraft server at the apex (root) of the domain.

1. Purchase a domain through Amazon Route53 in the AWS console. See https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/domain-register.html for details on how to do this.
	* You can, of course, use a domain purchased elsewhere and transfer that in to Route53, but I won't be covering that here.
1. Get the hosted zone ID of your domain. See https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/ListInfoOnHostedZone.html for details on how to do this. The hosted zone ID will be a random string of uppercase letters and numbers.
1. Fill in the `HOSTED_ZONE_ID` environment variable in your `.env` file with the hosted zone ID you got from the AWS console.
1. Proceed with the steps in _Deploying the Minecraft server_.

### Deploying the Minecraft server

1. Open a terminal and navigate to the project root directory.
1. Run `docker-compose -f docker-compose.terraform.init.yml up --build`
	* This will tell docker compose to run (`up`) the compose configuration in the init file (the file name after the `-f` flag), and to build (the `--build` flag) a fresh container to do so.
	* If docker compose prompts you for input when you run this, open a second terminal and run `docker attach instant-minecraft_terraform_1`. You can then type into the second terminal and it will feed that input to the container running in the first terminal.
1. Run `docker-compose -f docker-compose.terraform.plan.yml up --build`
	* Exactly as above, this will run the plan file which will prompt terraform to create a plan to deploy your infrastructure. You can and should inspect this plan in the console to make sure you don't have any errors and everything looks correct.
1. If you're happy with the plan, run `docker-compose -f docker-compose.terraform.apply.yml up --build`
	* This applies the plan and deploys the infrastructure to AWS. It will also tell you if it runs into any errors.
	* Terraform also runs the initial setup steps via the provisioner blocks for the `minecraft_server` resource in `minecraft.tf`. The provisioners create any necessary files, install dependencies, start a `crontab` job to backup your Minecraft server data every day, and start the Minecraft server.
1. Your Minecraft server should now be available at the domain name printed in the console.

## Configuring Minecraft for the first time

This project uses the [itzg/minecraft-server](https://hub.docker.com/r/itzg/minecraft-server) docker image, with [Paper](https://papermc.io/) and [Forge](https://files.minecraftforge.net/) enabled. When the server is first created, it will populate the `~/minecraft/data` folder with defaults for everything necessary to run your server. Please see the Paper documentation for the basics of configuring a paper server. If you would like to use Spigot, Bukkit, or the official server, just modify the `docker run` command in `~/minecraft/scripts/start-minecraft.sh` according to the [itzg/minecraft-server documentation](https://hub.docker.com/r/itzg/minecraft-server).

The primary files in `~/minecraft/data` for configuration are `server.properties`, `paper.yml`, `spigot.yml`, and `bukkit.yml`. White and black lists can be found in `whitelist.json`, `banned-players.json`, and `banned-ips.json`.

**WARNING:** By default, the server is completely open and public. You will want to set up a whitelist or other authentication solution after deploying the server.

## Managing your server
If you need to manage your server, such as restarting your docker container or manually messing around with files on your server, you should follow [AWS's instructions for connecting to your server](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-connect-methods.html). I like to use SSH in Ubuntu or Ubuntu through WSL (Windows Subsystem for Linux), but of course AWS provides a lovely browser-based SSH terminal as well. You should SSH into your server using the EC2 instance IP address generated by Terraform.

The Terraform setup creates scripts on the server under the `~/minecraft/scripts` directory. There are a few scripts which Terraform creates,and they are all designed to be idempotent:
1. `~/minecraft/scripts/start-minecraft.sh`: This script checks whether the Minecraft docker container is running, kills and removes it if so, and then starts it again. Invoking it multiple times just restarts Minecraft.
1. `~/minecraft/scripts/start-backup.sh`: This script adds a cron task to run `backup.sh` every 24 hours. If you run it again, it will not add extra copies of the task, it will just re-create the task.
1. `~/minecraft/scripts/backup.sh`: This backs up your Minecraft data folder to S3. When you run it, it creates a folder on S3 named using the current date and time and syncs a backup of `~/minecraft/data` to that folder. S3 is configured by default to retain backups for 7 days, since they can be quite large.
1. `~/minecraft/scripts/restore.sh`: This script restores a backup of your Minecraft server data folder from S3. You must pass it name of the folder in S3 which contains the backup you'd like to restore. For example, `/bin/bash ~/minecraft/scripts/restore.sh "Fri Mar 27 00:00:01 UTC 2020"`

Terraform will run all of the `start-` scripts when the server is first created, but feel free to run any of them via SSH.

If you ever need to re-create a specific part of the infrastructure, you can taint a resource by running `docker-compose -f docker-compose.terraform.plan.yml run terraform taint resource_type.resource_name` and then re-deploying. This will force the resource to be destroyed and re-created. Of course, substitute the resource type and name you want to re-create from the terraform code. For the EC2 instance itself, that would be `aws_instance.minecraft_server`.

**DIRE WARNING**: If you decide to directly change your infrastructure through the AWS console, such as destroying your instance or fiddling about with settings like instance size (pretty much anything other than managing the instance through SSH), you could definitely cause your infrastructure to become out of sync with Terraform. THIS IS BAD. You do not want to be manually digging through your Terraform state trying to fix things. If you want to make an INFRASTRUCTURE change, do it through Terraform. Otherwise, make sure you know what you're doing.

## Destroying your instance

If you want to totally wipe out your infrastructure, you can do the following:

1. Delete everything from your backup S3 bucket. If you don't do this, Terraform will throw up and tell you that it can't delete a bucket which has things in it. This can be useful if you want to destroy everything _but_ your backups--you can run the destroy command and it will destroy everything but the S3 buckets which contain objects.
1. Open a terminal and navigate to the project root directory.
1. Run `docker-compose -f docker-compose.terraform.destroy.yml up --build`
	* This will ask you to confirm destruction. Open a second terminal and run `docker attach instant-minecraft_terraform_1`. You can then type into the second terminal and it will feed that input to the container running in the first terminal.
	* This will really destroy everything, so be sure you want to proceed.

## Built With

* [itzg/minecraft-server](https://hub.docker.com/r/itzg/minecraft-server) - This docker image was awesome for easily setting up Minecraft on AWS.
* [Docker](https://www.docker.com/) Containers are great, this project uses docker containers.
* [Docker Compose](https://docs.docker.com/compose/) Docker compose is great, it's a very handy way to define and run Docker applications, especially those which need multiple containers running.
* [Terraform](https://www.terraform.io/) Terraform is a great, but sometimes scary tool. This is used to write infrastructure as code, and without it this whole project would be nearly impossible.

## Technical notes for those who care

* This Terraform setup is not the most secure it could be, in that it leaves SSH open to the public internet.
* This setup uses `aws s3 sync` to back up your Minecraft server data every day. It's really simple, but effective. If you want a fancier solution, customize! 
* This project uses docker-compose to run Terraform commands inside a Terraform container to avoid having to deal with configuration issues on your local machine. Each docker-compose `.yml` file has a separate command and environment variable mapping. I like this setup because it's easy to use, easy to version, and easy to modify. If you don't like this, I'm always open to suggestions.
* You'll notice that I run `dos2unix` on the scripts that Terraform creates. This is because I've been developing this on both Windows and Linux, and discovered that on Windows, Terraform created files with Windows line endings, causing the scripts to fail in really weird ways. The better solution is probably to not use provisioners like this, but it works well for a small project like this.

## Contributing

If you would like to contribute, open a PR, or an issue, or just message me.

## Versioning

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://github.com/your/project/tags). 

## Authors

* **Joey Triska**

See also the list of [contributors](https://github.com/your/project/contributors) who participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.MD) file for details

## Acknowledgments

* Thanks to Geoff Bourne (@itzg) for making a very nice Minecraft docker image.
* Thanks to the folks that build Docker and Terraform, too, because those are great tools to have in your toolbox.
