# DockerImage of Nginx with ECH support

This project is implemented based on the following projects:

1. [Experimental fork of Nginx with Encrypted Client Hello support](https://github.com/yaroslavros/nginx)
2. [docker-nginx-boringssl](https://github.com/nginx-modules/docker-nginx-boringssl/blob/main/mainline-alpine.Dockerfile)

## Quick Start

### generate ECH key

```
openssl genpkey -out /path/to/your/docker/mount/directory/ech.key -algorithm X25519
```

### prepare nginx.conf


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
        listen [::]:60500 quic reuseport ipv6only=off;
        listen [::]:60500 ssl ipv6only=off;
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

        add_header Alt-Svc 'h3=":60500";h3-29=":60500"';   # Advertise that HTTP/3 is available

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
        listen [::]:60500 quic;
        listen [::]:60500 ssl;
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

        add_header Alt-Svc 'h3=":60500";h3-29=":60500"';   # Advertise that HTTP/3 is available

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

### create docker container

```
docker run --name nginx -d \
    -p 60500:60500 \
    -p 60500:60500/udp \
    --restart unless-stopped \
    -v /path/to/your/docker/mount/directory:/etc/nginx \
    --log-opt max-size=2m \
    imhy123/nginx-ech:1.25.4-beta.2
```