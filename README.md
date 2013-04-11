# check_haproxy.rb

This is a simple script to check the status of haproxy backends.

It does not worry about if the frontend is up or not. It's only concerned
with backends.  It also doesn't differentiate between active and backup
backends.  A backend is a backend.

It will, however, check each frontend individually. At least, it should. We
only have one, so that's no tested.

It's *also* Ruby 1.8+ (because nagios servers are never up to date).

# Usage

```
define command {
  command_name check_haproxy_hosts
  command_line $USER1$/check_haproxy.rb --url http://$HOSTADDRESS$:5000/haproxy?stats --auth-user $ARG1$ --auth-pass $ARG2$ -w 10 -c 20
}

define service {
  use generic_schedule
  check_command check_haproxy_hosts!httpuser!httppass
  name haproxy
  service_description haproxy hosts
  hostgroup_name haproxy
}
```

That's how we use it. Our haproxies listen on INTERNAL:5000 (the hostaddress in nagios)
and on 127.0.0.1:5000.  If your port differs, change the port in the command.

It's got simple command line help, but basically, if a hosts has a higher %-age of
failed (ie: not UP) backends that either the warning or critical threshold, it alerts.

Although it will check each frontend invididually, if one is critical, the service is
marked critical, and the status message will indicate which.


