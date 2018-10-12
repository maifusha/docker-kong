FROM kong:0.9.9

LABEL maintainer="lixin <1045909037@qq.com>"

RUN yum-config-manager --disable epel >> /dev/null \
	&& yum install -y gcc unzip && yum clean all

COPY conf/kong /usr/local/share/lua/5.1/kong
COPY conf/kong.conf /etc/kong/kong.conf
COPY source/*.tar.gz /usr/local/src/

# https://www.openssl.org/source/
RUN cd /usr/local/src \
	&& tar -zxf openssl-1.0.2k.tar.gz && cd openssl-1.0.2k \
	&& ./config && make && make install \
	&& rm /usr/bin/openssl && ln -s /usr/local/ssl/bin/openssl /usr/bin/openssl

# http://openresty.org/en/using-luarocks.html
# http://luarocks.github.io/luarocks/releases/
RUN cd /usr/local/src \
	&& tar -zxf luarocks-2.4.2.tar.gz && cd luarocks-2.4.2 \
	&& ./configure --prefix=/usr/local/openresty/luajit --lua-suffix=jit --with-lua=/usr/local/openresty/luajit/ --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1 \
    && make && make install \
    && luarocks install lua-resty-auto-ssl \
    && mkdir /etc/resty-auto-ssl && chown nobody /etc/resty-auto-ssl

RUN rm -rf /usr/local/src

VOLUME /usr/local/kong/logs
