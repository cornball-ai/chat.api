
if (requireNamespace("tinytest", quietly = TRUE)) {
  Sys.setenv(R_USER_CACHE_DIR = tempfile("chat_api_cache_"),
             R_USER_DATA_DIR = tempfile("chat_api_data_"),
             R_USER_CONFIG_DIR = tempfile("chat_api_config_"))
  tinytest::test_package("chat.api")
}
