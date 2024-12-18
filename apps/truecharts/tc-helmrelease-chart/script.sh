helm template . --output-dir ../../production -f values/values.yml \
    && mkdir ../../production/actualserver \
    && mv ../../production/tc-helmrelease-chart/templates/* ../../production/actualserver \
    && rm -r ../../production/tc-helmrelease-chart