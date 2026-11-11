# Build and test the static rsync for the current (or given) platform and
# write the contents of out/ to ./out on the host:
#   docker buildx build --output out .
#   docker buildx build --platform linux/arm64 --output out .
FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS build
ARG SOURCE_DATE_EPOCH
WORKDIR /src
COPY . .
RUN ./recipe.sh
RUN ./test.sh out/rsync

FROM scratch
COPY --from=build /src/out/ /
