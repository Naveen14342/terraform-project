#!/bin/bash
# Update packages
apt-get update -y

snap install amazon-ssm-agent --classic
# Enable and start service
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service


# Install Apache
apt-get install -y apache2 unzip wget

# Enable and start Apache
systemctl enable apache2
systemctl start apache2

# Move into Apache's web root
cd /var/www/html

# Download the Tooplate template (zip file)
wget https://www.tooplate.com/zip-templates/2150_living_parallax.zip

# Unzip the template
unzip 2150_living_parallax.zip

# Move files into the web root
mv 2150_living_parallax/* .

# Clean up
rm -rf 2150_living_parallax 2150_living_parallax.zip
