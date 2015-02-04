require 'eventmachine'
require 'em-eventsource'
require 'lita/adapters/flowdock/message_handler'
require 'lita/adapters/flowdock/users_creator'

module Lita
  module Adapters
    class Flowdock < Adapter
      class Connector
        attr_reader :robot, :api_token, :organization, :flows, :source,
          :flowdock_client, :robot_id

        def initialize(robot, api_token, organization, flows, flowdock_client, robot_id)
          @robot = robot
          @api_token = api_token
          @organization = organization
          @flows = flows
          @flowdock_client = flowdock_client
          @robot_id = robot_id

          UsersCreator.create_users flowdock_client.get('/users')
        end

        def run
          EM.run do
            @source = EventMachine::EventSource.new(
              "https://#{api_token}@stream.flowdock.com/flows?filter=#{request_flows}",
              {query: 'text/event-stream'},
              {'Accept' => 'text/event-stream'}
            )

            source.open do |open|
              log.info("Connected to flowdock streaming API")
              robot.trigger(:connected)
            end

            source.message do |message|
              event = MultiJson.load(message)
              receive_message(event)
            end

            source.error do |error|
              log.error(error.inspect)
              EM.stop
            end

            source.start
          end
        end

        private

          def log
            Lita.logger
          end

          def receive_message(event)
            log.debug("Event received: #{event.inspect}")
            MessageHandler.new(robot, robot_id, event, flowdock_client).handle
          end

          def request_flows
            flows.map {|f| "#{organization}/#{f}" }.join(",")
          end
      end
    end
  end
end
