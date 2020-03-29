FROM ubuntu
RUN apt-get update --yes
RUN apt-get install --yes xz-utils make gcc flex bison bc patch
RUN apt-get install --yes libpcre3-dev libexpat1-dev libssl-dev libelf1
RUN apt-get install --yes gawk python3
