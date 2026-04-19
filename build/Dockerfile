# install go, required for terratest

# ghcr.io/sdobrau/terraform-ci:2026_19_04

FROM alpine:3cb067eab609612d81b4d82ff8ad71d73482bb3059a87b642d7e14f0ed659cde as builder

ARG VERSION
# ARG GH_TOKEN

RUN echo ${VERSION}
# grab terraform
USER root
RUN apk add --update --virtual .deps --no-cache gnupg
# prepare a safe environment
RUN useradd terraform-ci -m
USER terraform-ci
RUN mkdir $HOME/bin
ENV PATH $HOME/bin:$PATH
# prepare a safe environment

WORKDIR /tmp
RUN wget https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_amd64.zip && \
    wget https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_SHA256SUMS && \
    wget https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_SHA256SUMS.sig && \
    wget -qO- https://www.hashicorp.com/.well-known/pgp-key.txt | gpg --import && \
    gpg --verify terraform_${VERSION}_SHA256SUMS.sig terraform_${VERSION}_SHA256SUMS && \
    grep terraform_${VERSION}_linux_amd64.zip terraform_${VERSION}_SHA256SUMS | sha256sum -c && \
    unzip /tmp/terraform_${VERSION}_linux_amd64.zip -d /tmp && \
    mv /tmp/terraform /home/terraform-ci/bin/terraform && \
    rm -f /tmp/terraform_${VERSION}_linux_amd64.zip terraform_${VERSION}_SHA256SUMS ${VERSION}/terraform_${VERSION}_SHA256SUMS.sig && \
USER root
RUN apk del .deps

# add testing repository to be able to get opa and others
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories

# grab go for terratest, tflint, trivy
RUN apk update && apk add --no-cache git make musl-dev go clamav

USER terraform-ci
# ENV GOROOT /usr/lib/go
# ENV GOPATH /go
# ENV PATH /go/bin:$PATH
# ENV GH_TOKEN ${GH_TOKEN}

# * grab opa
# a9d9481e463e7af8cb1a2cd7c3deb764f0327b3281c54e632546c2f425fc0824 OK
RUN wget https://github.com/open-policy-agent/opa/releases/download/v1.15.2/opa_linux_amd64_static && \
    mv opa_linux_amd64_static $HOME/bin/opa

# * grab trivy
# ca4e4e8cb7cc3436f2b6979e9c4fd4e2623a66fcca1ad1fe12f8669967636ae2 OK
RUN wget https://github.com/aquasecurity/trivy/releases/download/v0.70.0/trivy_0.70.0_Linux-32bit.tar.gz && \
    tar xvf trivy_0.70.0_Linux-32bit.tar.gz && \
    mv /tmp/trivy $HOME/bin/trivy

# * grab python to install checkov
USER root
RUN apk add --no-cache pipx python3 # python3 already from previous
# USER terraform-ci
# RUN pipx install checkov
ENV PATH /root/.local/bin/:$PATH

USER terraform-ci
# * tflint
RUN wget https://github.com/terraform-linters/tflint/releases/download/v0.61.0/tflint_linux_amd64.zip && \
    wget https://github.com/terraform-linters/tflint/releases/download/v0.61.0/checksums.txt && \
    # TODO: there is no way to pass the github api key credential as a --build-arg GH_TOKEN variable inside the
    # jenkinsfile. so let's skip attestation for now
    #gh attestation verify checksums.txt -R terraform-linters/tflint && \
    unzip tflint_linux_amd64.zip -d $HOME/bin/ && \

# * betterleaks
WORKDIR /tmp
RUN git clone https://github.com/betterleaks/betterleaks
WORKDIR /betterleaks
RUN make build && \
    mv betterleaks /usr/local/bin/betterleaks

# clamav update db
RUN freshclam
# cleanup
WORKDIR /tmp/
RUN apk del make musl-dev && \
    rm -rf checksums.txt && \
    rm -rf tflint_linux_amd64.zip && \
    rm -rf betterleaks/ && \
    rm -rf trivy_0.70.0_Linux-32bit.tar.gz

HEALTHCHECK --interval=5m --timeout=5s --retries=1 \
    CMD tflint && opa && terraform && trivy
