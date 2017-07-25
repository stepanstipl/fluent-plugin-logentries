#
# Copyright 2017- larte
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fluent/plugin/output'
require 'yaml'
require_relative 'logentries_ssl/message_helper.rb'

module Fluent::Plugin
  module LogentriesSSL
    class Output < Fluent::Plugin::Output
      include Fluent::PluginHelper::Socket

      Fluent::Plugin.register_output('logentries_ssl', self)

      config_param :max_retries, :integer, default: 3
      config_param :le_host, :string, default: 'data.logentries.com'
      config_param :le_port, :integer, default: 443
      config_param :token, :string
      config_param :json, :bool, default: true
      config_param :verify_fqdn, :bool, default: true

      def start
        super
        log.trace "Creating connection to #{@le_host}"
        @_client = create_client
      end

      # apparently needed for msgpack_each in :write fluent Issue-1342
      def formatted_to_msgpack_binary
        true
      end

      def format(tag, _time, record)
        [tag, record].to_msgpack
      end

      def write(chunk)
        log.debug 'Writing records to logentries'
        chunk.msgpack_each do |tag, record|
          log.trace "Got token #{@token} for tag #{tag}"
          data = @json ? record.to_json : record
          payloads = MessageHelper.split_record(@token, "#{@token} #{data} \n")
          payloads.each do |payload|
            with_retries do
              client.write(payload)
            end
          end
        end
      end

      private

      def create_client
        socket_create(:tls, @le_host, @le_port, verify_fqdn: @verify_fqdn)
      end

      def close_client
        @_client.close if @_client
        @_client = nil
      end

      def client
        @_client ||= create_client
      end

      def retry?(n)
        n < @max_retries
      end

      def with_retries
        tries = 0
        begin
          yield
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ECONNABORTED,
               Errno::ENETUNREACH, Errno::ETIMEDOUT, Errno::EPIPE => e
          if retry?(tries += 1)
            log.warn 'Clould not push to logentries, reset and retry'\
                     "in #{2**tries} seconds. #{e.message}"
            sleep(2**tries)
            close_client
            retry
          end
          raise 'Could not push logs to Logentries'
        end
      end
    end
  end
end
