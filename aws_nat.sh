#!/bin/sh
if [ `id | cut -d= -f3 | cut -d\( -f1` = 0 ]; then
    echo "[i] -- Okay, you are root and can run this script"
else
    echo "[i] -- Sorry, you are NOT root."
fi

. /etc/hailo-nat/config

# Retrieve our network form facter
IP_eth0=`facter ipaddress_eth0`
IP_eth0_1=`facter ipaddress_eth0_1`

# Load credentials
. /etc/profile.d/aws-apitools-common.sh

# Get this instance's ID
INSTANCE_ID=`/usr/bin/curl --silent http://169.254.169.254/latest/meta-data/instance-id`

# Get the other NAT instance's IP
NAT_IP=`/usr/bin/ec2-describe-instances $NAT_ID -U $EC2_URL | grep INSTANCE | awk '{print $15}'`
echo `date` "[i] -- Starting NAT monitor"
echo `date` "[i] -- Adding this instance to $NAT_RT_ID default route on start"
/usr/bin/ec2-replace-route $NAT_ID -r 0.0.0.0/0 -i $INSTANCE_ID -U $EC2_URL

# If replace-route failed, then the route might not exist
if [ "$?" != "0" ]; then
   /usr/bin/ec2-create-route $NAT_RT_ID -r 0.0.0.0/0 -i $INSTANCE_ID -U $EC2_URL
fi
while [ . ]; do

  # Check health of other NAT instance
  pingresult=`ping -c $Num_Pings -W $Ping_Timeout $NAT_IP | grep time= | wc -l`

  # Check to see if any of the health checks succeeded, if not
  echo $pingresult
    if [ $pingresult = 0 ]; then
        pingresult_safe=`ping -c 3 -W 3 8.8.8.8 | grep time= | wc -l`
            if [ $pingresult_safe = 0 ]; then
                echo "Google is down? TROLOLOLOL"
                echo "Something is wrong in $INSTANCE_ID"> $EMAILMESSAGE
                echo "Look at me, now" >>$EMAILMESSAGE
                /bin/mail -s "$SUBJECT" "$EMAIL" < $EMAILMESSAGE
                exit 1
            fi
    # Set HEALTHY variables to unhealthy (0)
        ROUTE_HEALTHY=0
        NAT_HEALTHY=0
        STOPPING_NAT=0

    # NAT instance is unhealthy, loop while we try to fix it
        while [ "$NAT_HEALTHY" = "0" ]; do
            if [ "$ROUTE_HEALTHY" = "0" ]; then
                echo `date` "[i] -- Other NAT heartbeat failed, taking over $NAT_RT_ID default route"
                /usr/bin/ec2-replace-route $NAT_RT_ID -r 0.0.0.0/0 -i $INSTANCE_ID -U $EC2_URL
                ROUTE_HEALTHY=1
            fi
        # Check NAT state to see if we should stop it or start it again
        # Need to make stuff dynamic here
            if [ "$STOPPING_NAT" = "0" ]; then
                echo `date` "[i] -- Other NAT instance $NAT_STATE, attempting to stop"
                #/usr/bin/ec2-stop-instances $NAT_ID -U $EC2_URL
                /usr/bin/ec2-associate-address -i $INSTANCE_ID -p $IP_eth0_1 -a $EIP_ALLOC --region eu-west-1 --allow-reassociation
                echo 1 > /proc/sys/net/ipv4/ip_forward
                /sbin/iptables -t nat -A POSTROUTING -j MASQUERADE
                /sbin/iptables -t nat -I POSTROUTING -s $IP_eth0 -p tcp -j SNAT --to $IP_eth0_1
                /sbin/iptables -t nat -I POSTROUTING -s 0.0.0.0/0 -p tcp -j SNAT --to $IP_eth0_1
                STOPPING_NAT=1
            fi
            sleep $Wait_for_Instance_Stop
            done
        else
            sleep $Wait_Between_Pings
    fi
done
