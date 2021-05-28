### Scripts and Configs for Silk 

This repo will contain various customer-facing scripts and configurations. If you are here, chances are somebody directed you here for a specific file or files. 

You can use this repo to grab specific files via tools like wget. For instance, gathering the required configs for a Linux deployment may resemble:

```
sudo wget -O /etc/udev/rules.d/98-sdp-io.rules 'https://raw.githubusercontent.com/silk-us/scripts-and-configs/main/Configs/98-sdp-io.rules'  
sudo wget -O /etc/multipath.conf 'https://raw.githubusercontent.com/silk-us/scripts-and-configs/main/Configs/multipath.conf' 
```