FROM docker.elastic.co/elasticsearch/elasticsearch:8.19.0

USER elasticsearch

# Install Liferay-required analysis plugins at build time
RUN elasticsearch-plugin install --batch analysis-icu && \
    elasticsearch-plugin install --batch analysis-kuromoji && \
    elasticsearch-plugin install --batch analysis-smartcn && \
    elasticsearch-plugin install --batch analysis-stempel

# Override default log4j2 config:
#  - Use classic readable text format instead of ECS JSON
#  - Suppress noisy startup template/ILM registration messages
COPY --chown=elasticsearch:elasticsearch log4j2.properties /usr/share/elasticsearch/config/log4j2.properties

USER elasticsearch

EXPOSE 9200 9300
