import Config

if Config.config_env() in [:dev, :test] and File.exists?(".env") do
  DotenvParser.load_file(".env")
end
