# frozen_string_literal: true

module OrderManagement
  module Order
    class Updater
      attr_reader :order
      delegate :payments, :line_items, :adjustments, :shipments, :update_hooks, to: :order

      def initialize(order)
        @order = order
      end

      # This is a multi-purpose method for processing logic related to changes in the Order.
      # It is meant to be called from various observers so that the Order is aware of changes
      # that affect totals and other values stored in the Order.
      #
      # This method should never do anything to the Order that results in a save call on the
      # object with callbacks (otherwise you will end up in an infinite recursion as the
      # associations try to save and then in turn try to call +update!+ again.)
      def update
        update_totals

        if order.completed?
          update_payment_state

          # give each of the shipments a chance to update themselves
          shipments.each { |shipment| shipment.update!(order) }
          update_shipment_state
        end

        update_all_adjustments
        # update totals a second time in case updated adjustments have an effect on the total
        update_totals

        order.update_attributes_without_callbacks(
          {
            payment_state: order.payment_state,
            shipment_state: order.shipment_state,
            item_total: order.item_total,
            adjustment_total: order.adjustment_total,
            payment_total: order.payment_total,
            total: order.total
          }
        )

        run_hooks
      end

      def run_hooks
        update_hooks.each { |hook| order.__send__(hook) }
      end

      # Updates the following Order total values:
      #
      # - payment_total - the total value of all finalized Payments (excluding non-finalized Payments)
      # - item_total - the total value of all LineItems
      # - adjustment_total - the total value of all adjustments
      # - total - the "order total". This is equivalent to item_total plus adjustment_total
      def update_totals
        order.payment_total = payments.completed.map(&:amount).sum
        order.item_total = line_items.map(&:amount).sum
        order.adjustment_total = adjustments.eligible.map(&:amount).sum
        order.total = order.item_total + order.adjustment_total
      end

      # Updates the +shipment_state+ attribute according to the following logic:
      #
      # - shipped - when all Shipments are in the "shipped" state
      # - partial - when 1. at least one Shipment has a state of "shipped"
      #                       and there is another Shipment with a state other than "shipped"
      #                  or 2. there are InventoryUnits associated with the order that
      #                          have a state of "sold" but are not associated with a Shipment
      # - ready - when all Shipments are in the "ready" state
      # - backorder - when there is backordered inventory associated with an order
      # - pending - when all Shipments are in the "pending" state
      #
      # The +shipment_state+ value helps with reporting, etc. since it provides a quick and easy way
      #   to locate Orders needing attention.
      def update_shipment_state
        if order.backordered?
          order.shipment_state = 'backorder'
        else
          # get all the shipment states for this order
          shipment_states = shipments.states
          if shipment_states.size > 1
            # multiple shiment states means it's most likely partially shipped
            order.shipment_state = 'partial'
          else
            # will return nil if no shipments are found
            order.shipment_state = shipment_states.first
            # TODO inventory unit states?
            # if order.shipment_state && order.inventory_units.where(:shipment_id => nil).exists?
            #   shipments exist but there are unassigned inventory units
            #   order.shipment_state = 'partial'
            # end
          end
        end

        order.state_changed('shipment')
      end

      # Updates the +payment_state+ attribute according to the following logic:
      #
      # - paid - when +payment_total+ is equal to +total+
      # - balance_due - when +payment_total+ is less than +total+
      # - credit_owed - when +payment_total+ is greater than +total+
      # - failed - when most recent payment is in the failed state
      #
      # The +payment_state+ value helps with reporting, etc. since it provides a quick and easy way
      #   to locate Orders needing attention.
      def update_payment_state
        last_payment_state = order.payment_state

        order.payment_state = infer_payment_state
        track_payment_state_change(last_payment_state)

        order.payment_state
      end

      def update_all_adjustments
        order.adjustments.reload.each(&:update!)
      end

      def before_save_hook
        shipping_address_from_distributor
      end

      # Sets the distributor's address as shipping address of the order for those
      # shipments using a shipping method that doesn't require address, such us
      # a pickup.
      def shipping_address_from_distributor
        return if order.shipping_method.blank? || order.shipping_method.require_ship_address

        order.ship_address = order.address_from_distributor
      end

      private

      def round_money(value)
        (value * 100).round / 100.0
      end

      def infer_payment_state
        if failed_payments?
          'failed'
        elsif canceled_and_not_paid_for?
          'void'
        else
          infer_payment_state_from_balance
        end
      end

      def infer_payment_state_from_balance
        # This part added so that we don't need to override
        # order.outstanding_balance
        balance = order.outstanding_balance
        balance = -1 * order.payment_total if canceled_and_paid_for?

        infer_state(balance)
      end

      def infer_state(balance)
        if balance > 0
          'balance_due'
        elsif balance < 0
          'credit_owed'
        elsif balance.zero?
          'paid'
        end
      end

      # Tracks the state transition through a state_change for this order. It
      # does so until the last state is reached. That is, when the infered next
      # state is the same as the order has now.
      #
      # @param last_payment_state [String]
      def track_payment_state_change(last_payment_state)
        return if last_payment_state == order.payment_state

        order.state_changed('payment')
      end

      # Taken from order.outstanding_balance in Spree 2.4
      # See: https://github.com/spree/spree/commit/7b264acff7824f5b3dc6651c106631d8f30b147a
      def canceled_and_paid_for?
        order.canceled? && paid?
      end

      def canceled_and_not_paid_for?
        order.state == 'canceled' && order.payment_total.zero?
      end

      def paid?
        payments.present? && !payments.completed.empty?
      end

      def failed_payments?
        payments.present? && payments.valid.empty?
      end
    end
  end
end
