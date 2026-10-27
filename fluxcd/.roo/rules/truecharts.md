# truecharts

When working with truecharts helm chart values, fetch [upstream common values file](https://raw.githubusercontent.com/trueforge-org/truecharts/refs/heads/master/charts/library/common/values.yaml).

If you need to know default values for a specific chart, look it up by replacing <chart> with chart name under spec.chart.spec.chart key of the associated helmrelease file https://raw.githubusercontent.com/trueforge-org/truecharts/refs/heads/master/charts/stable/<chart>/values.yaml and fetch the page
