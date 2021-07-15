# frozen_string_literal: true
require 'fileutils'
require 'pathname'
require 'tempfile'
require 'securerandom'
require 'minitar'
require 'zlib'
require 'find'
require 'net/http'
require 'net/http/post/multipart'
require 'uri'
require 'listen'
require 'json'
require 'yaml'
require 'tty/prompt'

require_relative 'discourse_theme/version'
require_relative 'discourse_theme/config'
require_relative 'discourse_theme/ui'
require_relative 'discourse_theme/cli'
require_relative 'discourse_theme/client'
require_relative 'discourse_theme/downloader'
require_relative 'discourse_theme/uploader'
require_relative 'discourse_theme/watcher'
require_relative 'discourse_theme/scaffold'

module DiscourseTheme
  class ThemeError < StandardError; end
end
