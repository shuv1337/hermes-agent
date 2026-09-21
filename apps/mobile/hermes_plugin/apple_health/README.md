# Hermes Go Apple Health plugin

This user plugin receives read-only HealthKit samples from Hermes Go through
the authenticated dashboard API and exposes two tools in the `apple_health`
toolset. Data remains on the user's Hermes gateway.

Install the `apple_health` directory under `~/.hermes/plugins/`, explicitly
enable `apple-health`, and restart the dashboard/gateway. Only enable the
`apple_health` toolset on profiles that should see this sensitive dataset.

