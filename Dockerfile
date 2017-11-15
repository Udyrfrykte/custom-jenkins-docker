FROM debian:9

# pre-create jenkins user to lock its UID to 1500
RUN useradd -u 1500 jenkins

RUN apt-get update && apt-get install -y wget gpg locales

# setup locale
RUN echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && \
  dpkg-reconfigure --frontend=noninteractive locales && \
  update-locale LANG=en_US.UTF-8
ENV LANG en_US.UTF-8

ENV TINI_VERSION 0.14.0
ENV TINI_SHA 6c41ec7d33e857d4779f14d9c74924cab0c7973485d2972419a3b7c7620ff5fd

# Use tini as subreaper in Docker container to adopt zombie processes
RUN wget -q -O /bin/tini https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-static-amd64 \
  && chmod +x /bin/tini \
  && echo "$TINI_SHA  /bin/tini" | sha256sum -c -

# install Oracle JDK
RUN echo 'deb http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main' >| /etc/apt/sources.list.d/oracle-jdk.list \
  && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7B2C3B0889BF5709A105D03AC2518248EEA14886 \
  && apt-get update \
  && echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections \
  && echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections \
  && apt-get install -y oracle-java8-installer

# install jenkins
#  && apt-get install -y ca-certificates-java openjdk-8-jre-headless \
RUN echo 'deb http://pkg.jenkins-ci.org/debian binary/' >| /etc/apt/sources.list.d/jenkins.list \
  && wget -q -O - https://pkg.jenkins.io/debian/jenkins.io.key | apt-key add - \
  && apt-get update \
  && apt-get install -y --ignore-missing jenkins=2.85

# set jenkins home directory to the right value
RUN usermod -d /var/lib/jenkins jenkins

# backup the initial java truststore
RUN mkdir /etc/ssl/certs/java \
  && mv /usr/lib/jvm/java-8-oracle/jre/lib/security/cacerts /etc/ssl/certs/java/cacerts \
  && ln -s /etc/ssl/certs/java/cacerts /usr/lib/jvm/java-8-oracle/jre/lib/security/cacerts \
  && cp /etc/ssl/certs/java/cacerts /etc/ssl/certs/java/cacerts.orig

ADD start.sh /

# install tools
RUN apt-get install -y git curl sshpass ksh

# install maven
RUN apt-get install -y maven

# install sbt
RUN echo "deb http://dl.bintray.com/sbt/debian /" | tee -a /etc/apt/sources.list.d/sbt.list \
  && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 2EE0EA64E40A89B84B2DF73499E82A75642AC823 \
  && apt-get update \
  && apt-get install sbt

# install anaconda
RUN apt-get install -y bzip2 binutils libc-dev \
  && wget -O /opt/anaconda-install.sh https://repo.continuum.io/archive/Anaconda2-4.4.0-Linux-x86_64.sh \
  && bash /opt/anaconda-install.sh -b -p /opt/anaconda \
  && bash -c '. /opt/anaconda/bin/activate && conda install -y gcc py-xgboost' \
  && rm -rf /opt/anaconda-install.sh

# install ansible
RUN apt-get install -y python2.7 python-pip \
  && pip install ansible==2.3.2.0

# install cqlsh (reusing pip from ansible) and dirty hack to make it work with strange DSE version
RUN pip install cqlsh==5.0.3 \
  && sed -i 's/DEFAULT_PROTOCOL_VERSION = 4/DEFAULT_PROTOCOL_VERSION = 3/' /usr/local/bin/cqlsh

# NODE #
# nvm environment variables
ENV NVM_DIR /usr/local/nvm
ENV NODE_VERSION 6.9.1

# install nvm
# https://github.com/creationix/nvm#install-script
RUN curl --silent -o- https://raw.githubusercontent.com/creationix/nvm/v0.31.2/install.sh | bash

# install node and npm
RUN bash -c 'source $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default'

# add node and npm to path so the commands are available
ENV NODE_PATH $NVM_DIR/v$NODE_VERSION/lib/node_modules
ENV PATH $NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

RUN npm install -g bower gulp-cli && npm install gulp -D
########

# install libs required by docker
# docker socket and binary will be mounted from host but we need to put jenkins in the docker group
RUN https_proxy="${proxy}" http_proxy="${proxy}" apt-get install -y libltdl7 \
  && groupadd -g 169 docker \
  && usermod -a -G docker jenkins

# Jenkins home directory is a volume, so configuration and build history
# can be persisted and survive image upgrades
VOLUME /var/lib/jenkins

# for main web interface:
EXPOSE 8080

USER jenkins
ENTRYPOINT ["/bin/tini", "--", "/start.sh"]
