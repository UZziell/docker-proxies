#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

#####  ONLY CHANGE THIS BLOCK  ######
PROG=/usr/bin/ssh
SSH_KEY_FILE=
SSH_HOST=
SSH_PORT=
#####  ONLY CHANGE THIS BLOCK  ######

start_service() {
    procd_open_instance
    procd_set_param command $PROG -I 300 -N -t -q -y -y -W 10240 -i $SSH_KEY_FILE -R 127.0.0.1:2228:0.0.0.0:80 -R 127.0.0.1:2222:0.0.0.0:22 -g -p $SSH_PORT -l root $SSH_HOST

    procd_set_param user root
    procd_set_param limits core="unlimited"
    procd_set_param limits nofile="10000 10000"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn "${respawn_threshold:-3600}" "${respawn_timeout:-5}" "${respawn_retry:-999}"
    procd_close_instance

    sleep 5
    echo "ssh-everse is started!"
}

stop_service() {
    service_stop $PROG
    # /usr/sbin/iptables -D FORWARD -o tun0 -j ACCEPT
    echo "ssh-reverse is stopped!"
}

reload_service() {
    stop
    sleep 5s
    echo "ssh-reverse is restarted!"
    start
}

service_triggers() {
    local ifaces
    config_load "$NAME"
    config_get ifaces "main" "ifaces"
    procd_open_trigger
    for iface in $ifaces;
    do
        procd_add_interface_trigger "interface.*.up" $iface /etc/init.d/$NAME restart
    done
    procd_close_trigger
    procd_add_reload_trigger "$NAME"
}
