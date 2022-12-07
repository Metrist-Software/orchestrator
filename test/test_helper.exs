
# Mark integration tests `external` so we can manually
# run the more expensive test suite.
ExUnit.configure(exclude: [external: true])

ExUnit.start()
