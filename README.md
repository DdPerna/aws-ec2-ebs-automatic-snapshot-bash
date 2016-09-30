aws-ec2-ebs-automatic-snapshot-bash
===================================

####Bash script for Automatic EBS Snapshots and Cleanup on Amazon Web Services (AWS)

Written by  **[AWS Consultants - Casey Labs Inc.] (http://www.caseylabs.com)**

*Contact us for all your Amazon Web Services consulting needs!*

Forked by DdPerna

===================================

**Differences**

Instead of placing the script on each box that needs to backup it's ebs volume, Run it from one instance with the proper IAM role and create the backup tag for the instances you want to snapshot.

**How it works:**
ebs-snapshot.sh will:
- Gather a list of all volume IDs attached to an instance that has a tag called "Backup" with a value of "yes" (case sensitive)
- Take a snapshot of each attached volume
- The script will then delete all associated snapshots taken by the script that are older than 27 days

Pull requests greatly welcomed!

===================================

**REQUIREMENTS**

**IAM User:** The instance running the script requires an IAM role, with the following security policy attached:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1426256275000",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSnapshot",
                "ec2:CreateTags",
                "ec2:DeleteSnapshot",
                "ec2:DescribeSnapshots",
                "ec2:DescribeVolumes"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```
<br />

**AWS CLI:** This script requires the AWS CLI tools to be installed.

First, make sure Python pip is installed:
```
# Ubuntu
sudo apt-get install python-pip -y

# Red Hat/CentOS
sudo yum install python-pip -y
```
Then install the AWS CLI tools: 
```
sudo pip install awscli
```
Once the AWS CLI has been installed, you'll need to configure it with the credentials of the IAM user created above:

```
sudo aws configure

AWS Access Key ID: (Enter in the IAM credentials generated above.)
AWS Secret Access Key: (Enter in the IAM credentials generated above.)
Default region name: (The region that this instance is in: i.e. us-east-1, eu-west-1, etc.)
Default output format: (Enter "text".)```
```
<br />

**Install Script**: Download the latest version of the snapshot script and make it executable:
```
cd ~
wget https://raw.githubusercontent.com/DdPerna/aws-ec2-ebs-automatic-snapshot-bash/master/ebs-snapshot.sh
chmod +x ebs-snapshot.sh
mkdir -p /opt/aws
sudo mv ebs-snapshot.sh /opt/aws/
```

You should then setup a cron job in order to schedule a weekly backup. Example crontab jobs:
```
# snapshot ebs volumes every sunday at 1am
0 1 * * 0 root  AWS_CONFIG_FILE="/root/.aws/config" /opt/aws/ebs-snapshot.sh

# Or written another way:
AWS_CONFIG_FILE="/root/.aws/config" 
55 22 * * * root  /opt/aws/ebs-snapshot.sh
```

To manually test the script:
```
sudo /opt/aws/ebs-snapshot.sh
```
