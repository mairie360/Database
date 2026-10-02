# gosu shipped by the postgres image is built with an old Go toolchain, so Trivy
# blocks the release on stdlib CVEs. Rebuild the same upstream release with a
# current Go and replace it.
FROM golang:1.26-bookworm AS gosu
ARG GOSU_VERSION=1.19
ARG GOSU_COMMIT=6456aaa0f3c854d199d0f037f068eb97515b7513
ENV CGO_ENABLED=0
RUN set -eux; \
	git clone --depth 1 --branch "$GOSU_VERSION" https://github.com/tianon/gosu.git /src; \
	test "$(git -C /src rev-parse HEAD)" = "$GOSU_COMMIT"; \
	cd /src; \
	go build -trimpath -ldflags '-d -w' -o /gosu .

FROM postgres:18.6-bookworm
COPY --from=gosu /gosu /usr/local/bin/gosu
RUN gosu nobody true
