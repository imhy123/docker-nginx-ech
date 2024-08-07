# Nginx Docker image featuring ECH support

[中文](README.zh.md)

This project is implemented based on the following projects:

1. [Experimental fork of Nginx with Encrypted Client Hello support](https://github.com/yaroslavros/nginx)
2. [docker-nginx-boringssl](https://github.com/nginx-modules/docker-nginx-boringssl/blob/main/mainline-alpine.Dockerfile)

## Quick Start

### Docker Container

#### Generate ECH key

```
openssl genpkey -out /path/to/your/docker/mount/directory/ech.key -algorithm X25519
```

#### Prepare nginx.conf


vim /path/to/your/docker/mount/directory/nginx.conf

```
user root;
events {
    worker_connections  1024;
}

http {
    client_max_body_size 200m;

    server {
        # "reuseport" and "ipv6only=off" only need to configure once
        listen [::]:54321 quic reuseport ipv6only=off;
        listen [::]:54321 ssl ipv6only=off;
        http2 on;
        http3 on;
        http3_hq on;

        server_name a.example.com;
        proxy_buffering off;

        # ech key, only need to configure once
        ssl_ech a.example.com 1 key=/etc/nginx/ech.key;

        ssl_certificate /etc/nginx/a.example.com.pem;
        ssl_certificate_key /etc/nginx/a.example.com.key;

        ssl_protocols TLSv1.3;
        ssl_prefer_server_ciphers on;

        ssl_session_timeout 1d;
        ssl_session_cache shared:MozSSL:10m;  # about 40000 sessions
        ssl_session_tickets off;

        add_header Alt-Svc 'h3=":54321";h3-29=":54321"';   # Advertise that HTTP/3 is available

        # HSTS
        add_header Strict-Transport-Security "max-age=31536000" always;

        location / {
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_pass http://calibre:8083;
        }

        location /.well-known/origin-svcb {
            add_header Content-Type application/json;
            return 200 '{"enable":$ssl_ech,"endpoints":[{"ech":"$ssl_ech_config"}]}';
        }
    }

    server {
        listen [::]:54321 quic;
        listen [::]:54321 ssl;
        http2 on;
        http3 on;
        http3_hq on;

        server_name b.example.com;
        proxy_buffering off;

        ssl_certificate /etc/nginx/b.example.com.pem;
        ssl_certificate_key /etc/nginx/b.example.com.key;

        ssl_protocols TLSv1.3;
        ssl_prefer_server_ciphers on;

        ssl_session_timeout 1d;
        ssl_session_cache shared:MozSSL:10m;  # about 40000 sessions
        ssl_session_tickets off;

        add_header Alt-Svc 'h3=":54321";h3-29=":54321"';   # Advertise that HTTP/3 is available

        # HSTS
        add_header Strict-Transport-Security "max-age=31536000" always;

        location / {
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_pass http://calibre2:8083;
        }

        location /.well-known/origin-svcb {
            add_header Content-Type application/json;
            return 200 '{"enable":$ssl_ech,"endpoints":[{"ech":"$ssl_ech_config"}]}';
        }
    }

}

```

#### Create Docker Container

```
docker run --name nginx -d \
    -p 54321:54321 \
    -p 54321:54321/udp \
    --restart unless-stopped \
    -v /path/to/your/docker/mount/directory:/etc/nginx \
    --log-opt max-size=2m \
    imhy123/nginx-ech:1.25.4-beta.2
```

Use `docker logs -f nginx` to retrieve the ECH public key, like `server a.example.com ECH config for HTTPS DNS record ech="THISISECHPUBLICKEY"`.

### DNS Record

#### A/AAAA DNS Record

Like any standard website, start by adding an A(for IPv4) or AAAA(for IPv6) record with your DNS provider to point to your server; of course, a CNAME record would work as well.

```
A, a.example.com, 1.1.1.1
A, b.example.com, 1.1.1.1
AAAA, a.example.com, abcd:ef01:2345:6789:abcd:ef01:2345:6789
AAAA, b.example.com, abcd:ef01:2345:6789:abcd:ef01:2345:6789
```

#### HTTPS DNS Record

An HTTPS DNS record is a special type of DNS record, with a type value of 65. ECH needs to work in conjunction with your HTTPS DNS record. If the service is offered on port 443, only a single HTTPS DNS record named "a.example.com" is required. However, if the service is provided on a non-443 port, a record in the format _port._protocol.name is necessary. For example, if the service is on port 54321, an HTTPS DNS record named "_54321._https.a" should be provided.

The record's value must include fields such as alpn, port, ech, ipv4hint (if available), and ipv6hint (if available), with the ech field being the ECH public key retrieved via docker logs.

Therefore, in this case, the HTTPS DNS record to be added with the DNS service provider is as follows:

```
HTTPS, _54321._https.a, alpn="h3" port="54321" ipv4hint="1.1.1.1" ipv6hint="abcd:ef01:2345:6789:abcd:ef01:2345:6789" ech="THISISECHPUBLICKEY"
HTTPS, _54321._https.b, alpn="h3" port="54321" ipv4hint="1.1.1.1" ipv6hint="abcd:ef01:2345:6789:abcd:ef01:2345:6789" ech="THISISECHPUBLICKEY"
```

### Testing and Usage

#### Testing DNS Record

You can directly use the dig command (a newer version of dig may be required) to check if the DNS record has taken effect: `dig @8.8.8.8 a.example.com https`.

#### Usage

To use ECH, you need to set up a DOH (DNS over HTTPS) server in Chrome/Firefox browsers. For example, in Chrome, you can set a DOH server in Settings > Privacy and security > Security, such as "https://dns.google/dns-query".

Once everything is set up, you can access "https://a.example.com:54321/.well-known/origin-svcb" to check if your ECH is working correctly.