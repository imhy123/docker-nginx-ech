ARG NGINX_VERSION=1.25.4

FROM nginx:${NGINX_VERSION} AS build

WORKDIR /src
RUN apt-get update && \
    apt-get install -y git gcc make g++ cmake perl ninja-build && \
    git clone https://boringssl.googlesource.com/boringssl && \
    cd boringssl && \
    cmake -DCMAKE_BUILD_TYPE=Release -GNinja -B build && \
    ninja -C build

RUN apt-get install -y libperl-dev libpcre3-dev && \
    git clone https://github.com/yaroslavros/nginx && \
    cd nginx && \
    auto/configure `nginx -V 2>&1 | sed "s/ \-\-/ \\\ \n\t--/g" | grep "\-\-" | grep -ve opt= -e param= -e build=` \
                   --build=nginx-ech --with-debug  \
                   --with-cc-opt="-I/src/boringssl/include" --with-ld-opt="-L/src/boringssl/build/ssl -L/src/boringssl/build/crypto" && \
    make

FROM nginx:${NGINX_VERSION} 

COPY --from=build /src/nginx-quic/objs/nginx /usr/sbin

ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 80

STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]