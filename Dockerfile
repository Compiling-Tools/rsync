# Build and test the static rsync for the current (or given) platform and
# write the contents of out/ to ./out on the host:
#   docker buildx build --output out .
#   docker buildx build --platform linux/arm64 --output out .
FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS build
ARG SOURCE_DATE_EPOCH
WORKDIR /src
COPY . .
RUN ./recipe.sh
RUN ./test.sh out/rsync

FROM scratch
COPY --from=build /src/out/ /
