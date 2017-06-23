FROM alpine

# install awscli tool and curl
RUN apk add --no-cache \
        jq \
        curl \
        openssl \
        python2 \
        py-pip \
 && pip install awscli \
 && apk del --no-cache \
        py-pip

# add Route53 updater script
ADD route53-updater /usr/local/bin/
RUN chmod +x /usr/local/bin/route53-updater

CMD ["route53-updater"]
