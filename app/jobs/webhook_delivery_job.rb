# frozen_string_literal: true

require "faraday"

# Deliver a webhook payload
# As a delayed job, it can run asynchronously and handle retries.
class WebhookDeliveryJob < ApplicationJob
  queue_as :default

  def perform(url, event, payload)
    body = {
      id: job_id,
      at: Time.zone.now.to_s,
      event: event,
      data: payload,
    }

    notify_endpoint(url, body)
  end

  def notify_endpoint(url, body)
    connection = Faraday.new(
      request: { timeout: 30 },
      headers: {
        'User-Agent' => 'openfoodnetwork_webhook/1.0',
        'Content-Type' => 'application/json',
      }
    )
    connection.post(url, body.to_json)
  end
end
