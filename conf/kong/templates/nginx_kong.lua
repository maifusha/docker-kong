return [[
resolver ${{DNS_RESOLVER}} ipv6=off;
charset UTF-8;

error_log logs/error.log ${{LOG_LEVEL}};
access_log off;

> if anonymous_reports then
${{SYSLOG_REPORTS}}
> end

> if nginx_optimizations then
send_timeout 60s;
keepalive_timeout 60s;
client_body_timeout 60s;
client_header_timeout 60s;
tcp_nopush on;
proxy_buffer_size 128k;
proxy_buffers 4 256k;
proxy_busy_buffers_size 256k;
reset_timedout_connection on;
> end

client_max_body_size 4m;
client_body_buffer_size 1m;
proxy_ssl_server_name on;
underscores_in_headers on;

real_ip_header X-Forwarded-For;
set_real_ip_from 10.0.0.0/8;
set_real_ip_from 172.16.0.0/12;
set_real_ip_from 192.168.0.0/16;
real_ip_recursive on;

lua_package_path '${{LUA_PACKAGE_PATH}};;';
lua_package_cpath '${{LUA_PACKAGE_CPATH}};;';
lua_code_cache ${{LUA_CODE_CACHE}};
lua_max_running_timers 4096;
lua_max_pending_timers 16384;
lua_shared_dict kong 4m;
lua_shared_dict auto_ssl 2m;
lua_shared_dict cache ${{MEM_CACHE_SIZE}};
lua_shared_dict cache_locks 100k;
lua_shared_dict cassandra 1m;
lua_shared_dict cassandra_prepared 5m;
lua_socket_log_errors off;
> if lua_ssl_trusted_certificate then
lua_ssl_trusted_certificate '${{LUA_SSL_TRUSTED_CERTIFICATE}}';
lua_ssl_verify_depth ${{LUA_SSL_VERIFY_DEPTH}};
> end

init_by_lua_block {
    require 'resty.core'
    kong = require 'kong'
    kong.init()
    auto_ssl = (require "resty.auto-ssl").new()
> if allow_domain then
    auto_ssl:set("allow_domain", function(domain)
        return ngx.re.match(domain, "${{ALLOW_DOMAIN}}", "ijo")
    end)
> end
    auto_ssl:set("renew_check_interval", 604800)

    auto_ssl:set("storage_adapter", "${{STORAGE_ADAPTER}}")

    auto_ssl:set("redis", {
      host = "${{REDIS_HOST}}",
> if redis_auth then
      auth = "${{REDIS_AUTH}}",
> end
      prefix = "${{REDIS_PREFIX}}"
    })

    auto_ssl:init()
}

init_worker_by_lua_block {
    kong.init_worker()
    auto_ssl:init_worker()
}

server {
    server_name kong;
    listen ${{PROXY_LISTEN}};
    error_page 404 408 411 412 413 414 417 /kong_error_handler;
    error_page 500 502 503 504 /kong_error_handler;

> if ssl then
    listen ${{PROXY_LISTEN_SSL}} ssl;
    ssl_certificate ${{SSL_CERT}};
    ssl_certificate_key ${{SSL_CERT_KEY}};
    ssl_prefer_server_ciphers on;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers 'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS';
    ssl_certificate_by_lua_block {
        auto_ssl:ssl_certificate()
    }
> end

    location / {
        set $upstream_host nil;
        set $upstream_url nil;

        access_by_lua_block {
            kong.access()
        }

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $upstream_host;
        proxy_pass_header Server;
        proxy_pass $upstream_url;

        header_filter_by_lua_block {
            kong.header_filter()
        }

        body_filter_by_lua_block {
            kong.body_filter()
        }

        log_by_lua_block {
            kong.log()
        }
    }

    location = /kong_error_handler {
        internal;
        content_by_lua_block {
            require('kong.core.error_handlers')(ngx)
        }
    }

    location /.well-known/acme-challenge/ {
        content_by_lua_block {
            auto_ssl:challenge_server()
        }
    }
}

server {
    listen 127.0.0.1:8999;
    location / {
        content_by_lua_block {
            auto_ssl:hook_server()
        }
    }
}

server {
    server_name kong_admin;
    listen ${{ADMIN_LISTEN}};

    client_max_body_size 10m;
    client_body_buffer_size 10m;

    location / {
        default_type application/json;
        content_by_lua_block {
            ngx.header['Access-Control-Allow-Origin'] = '*'
            if ngx.req.get_method() == 'OPTIONS' then
                ngx.header['Access-Control-Allow-Methods'] = 'GET,HEAD,PUT,PATCH,POST,DELETE'
                ngx.header['Access-Control-Allow-Headers'] = 'Content-Type'
                ngx.exit(204)
            end

            require('lapis').serve('kong.api')
        }
    }

    location /nginx_status {
        internal;
        access_log off;
        stub_status;
    }

    location /robots.txt {
        return 200 'User-agent: *\nDisallow: /';
    }
}
]]