# 支持ECH的NGINX Docker镜像

[English](README.md)

本项目基于下面的项目进行实现:

1. [Experimental fork of Nginx with Encrypted Client Hello support](https://github.com/yaroslavros/nginx)
2. [docker-nginx-boringssl](https://github.com/nginx-modules/docker-nginx-boringssl/blob/main/mainline-alpine.Dockerfile)

## 快速开始

### Docker容器

#### 生成 ECH key

```
openssl genpkey -out /path/to/your/docker/mount/directory/ech.key -algorithm X25519
```

#### 准备 nginx.conf


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

#### 创建Docker容器

```
docker run --name nginx -d \
    -p 54321:54321 \
    -p 54321:54321/udp \
    --restart unless-stopped \
    -v /path/to/your/docker/mount/directory:/etc/nginx \
    --log-opt max-size=2m \
    imhy123/nginx-ech:1.25.4-beta.2
```

执行 `docker logs -f nginx` 来获取 ECH public key, 日志形如 `server a.example.com ECH config for HTTPS DNS record ech="THISISECHPUBLICKEY"`.

### DNS记录

#### A/AAAA 记录

像普通的网站一样，先在你的DNS服务提供商中添加A记录(IPv4)或者AAAA记录(IPv6)指向你的服务器，当然CNAME也可以：

```
A, a.example.com, 1.1.1.1
A, b.example.com, 1.1.1.1
AAAA, a.example.com, abcd:ef01:2345:6789:abcd:ef01:2345:6789
AAAA, b.example.com, abcd:ef01:2345:6789:abcd:ef01:2345:6789
```

#### HTTPS DNS记录

HTTPS DNS记录是一种特殊的DNS记录、其类型为65。ECH需要配合如果你的HTTPS DNS记录来使用，如果服务提供在443端口，则只需要提供一条名称为 "a.example.com" 的HTTPS DNS记录即可；如果服务提供在非443端口，则需要提供格式为 `_port._protocol.name` 的记录，例如在 54321 端口提供服务，则需要提供一条名称为 "_54321._https.a" 的 HTTPS DNS记录。

记录的值需要提供 alpn、port、ech、ipv4hint(如有)、ipv6hint(如有) 等字段，其中的ech字段即为通过 docker logs 获取到的 ECH public key。

因此在本例中，需要向DNS服务提供商中添加的HTTPS DNS记录如下：

```
HTTPS, _54321._https.a, alpn="h3" port="54321" ipv4hint="1.1.1.1" ipv6hint="abcd:ef01:2345:6789:abcd:ef01:2345:6789" ech="THISISECHPUBLICKEY"
HTTPS, _54321._https.b, alpn="h3" port="54321" ipv4hint="1.1.1.1" ipv6hint="abcd:ef01:2345:6789:abcd:ef01:2345:6789" ech="THISISECHPUBLICKEY"
```

### 测试与使用

#### 测试DNS记录

可以直接使用dig命令（可能需要比较新的dig版本）来检查DNS记录有没有生效：`dig @8.8.8.8 a.example.com https`。

#### 使用

使用ECH需要在Chrome/Firefox浏览器中设置了DOH(DNS over HTTPS)服务器，如Chrome可以在 设置-隐私与安全-安全 里面设置一个DOH服务器，如 "https://dns.google/dns-query"。

一切都准备好后，即可以访问通过 "https://a.example.com:54321/.well-known/origin-svcb" 来检查你的ECH是否正常工作。