# Build and test the static rsync for the current (or given) platform and
# write the contents of out/ to ./out on the host:
#   docker buildx build --output out .
#   docker buildx build --platform linux/arm64 --output out .
FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a AS build
ARG SOURCE_DATE_EPOCH
WORKDIR /src
COPY . .
RUN ./recipe.sh
RUN ./test.sh out/rsync

FROM scratch
COPY --from=build /src/out/ /
