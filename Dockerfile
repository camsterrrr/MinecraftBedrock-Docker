FROM ubuntu:latest

RUN mkdir /mincraftBedrock && mkdir /mincraftBedrock/serverCode && \
    apt update && apt upgrade && \
    apt install -y curl wget unzip openssl grep screen

WORKDIR /minecraftBedrock/serverCode

COPY ./serverCode .

RUN ls -la
    
EXPOSE 19132/udp 19133/udp 19132/tcp 19133/tcp

CMD ["./bedrock_server"]