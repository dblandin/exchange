ActiveAdmin.register Order do
  actions :all, except: %i[create update destroy new edit]
  # TODO: change sort order
  config.sort_order = 'state_updated_at_desc'

  scope :all
  scope('Active Orders', default: true) { |scope| scope.active }
  scope('Pickup Orders') { |scope| scope.where(state: [ Order::APPROVED, Order::FULFILLED, Order::SUBMITTED ], fulfillment_type: Order::PICKUP ) }
  scope('Fulfillment Overdue') { |scope| scope.approved.where('state_expires_at < ?', Time.now) }
  scope('Pending & Abandoned Orders') { |scope| scope.where(state: [ Order::ABANDONED, Order::PENDING ]) }

  filter :id_eq, label: 'Order Id'
  filter :mode, as: :check_boxes, collection: proc { Order::MODES }, label: 'Mode'
  filter :code_eq, label: 'Order Code'
  filter :seller_id_eq, label: 'Seller Id'
  filter :buyer_id_eq, label: 'Buyer Id'
  filter :created_at, as: :date_range, label: 'Submitted Date'
  filter :fulfillment_type, as: :check_boxes, collection: proc { Order::FULFILLMENT_TYPES }
  filter :state, as: :check_boxes, collection: proc { Order::STATES }
  filter :state_reason, as: :check_boxes, collection: proc { Order::REASONS.values.map(&:values).flatten.uniq.map!(&:humanize) }

  index do
    column :code do |order|
      link_to order.code, admin_order_path(order.id)
    end
    column :state
    column :fulfillment_type
    column 'Last Admin Action' do |order|
      order.last_admin_note&.note_type&.humanize
    end
    column 'Submitted At', :created_at
    column 'Last Updated At', :updated_at
    column :state_expires_at
    column 'Items Total' do |order|
       number_to_currency(order.items_total_cents.to_f/100)
    end
    column 'Buyer Total' do |order|
       number_to_currency(order.buyer_total_cents.to_f/100)
    end
  end

  member_action :refund, method: :post do
    OrderCancellationService.new(resource).refund!
    redirect_to resource_path, notice: "Refunded!"
  end
  
  member_action :approve_order, method: :post do
    OrderApproveService.new(resource, current_user[:id]).process!
    redirect_to resource_path, notice: "Order approved!"
  end

  member_action :confirm_pickup, method: :post do
    if resource.fulfillment_type == Order::PICKUP
      OrderService.confirm_pickup!(resource, current_user[:id])
    end
    redirect_to resource_path, notice: "Fulfillment confirmed!"
  end

  action_item :refund, only: :show do
    if [Order::APPROVED, Order::FULFILLED].include? order.state
      link_to 'Refund', refund_admin_order_path(order), method: :post, data: {confirm: 'Are you sure you want to refund this order?'}
    end
  end

  
  action_item :approve_order, only: :show do
    if order.state == Order::SUBMITTED
      link_to 'Approve Order', approve_order_admin_order_path(order), method: :post, data: {confirm: 'Approve this order?'}
    end
  end

  action_item :confirm_pickup, only: :show do
    if order.state == Order::APPROVED && order.fulfillment_type == Order::PICKUP
      link_to 'Confirm Pickup', confirm_pickup_admin_order_path(order), method: :post, data: {confirm: 'Confirm order pickup?'}
    end
  end

  sidebar :contact_info, only: :show do

    table_for order.line_items do
      column '' do |line_item|
        artwork_info = GravityService.get_artwork(line_item.artwork_id)
        if artwork_info.present?
          if artwork_info[:images].kind_of?(Array)
            square_image = artwork_info[:images].find { |im| im[:image_urls].key?(:square) }
            img :src => square_image[:image_urls][:square], :width => "100%"
          end
          br
          if artwork_info.key?(:title)
            link_to "#{artwork_info[:title]} by #{artwork_info[:artist][:name]}", artsy_view_artwork_url(line_item.artwork_id)
          end
        else
          h3 "Failed to fetch artwork"
        end
      end
    end

    panel "Buyer Information" do
      user_info = GravityService.get_user(order.buyer_id)

      attributes_table_for order do
        if user_info.present?
          row 'Name' do
            user_info[:name]
          end
          row 'Location' do
            if user_info[:location][:display].empty?
              div "No location for user"
            else
              user_info[:location][:display]
            end
          end
          row 'Email' do
            user_info[:email]
          end
        end
        if order.fulfillment_type == Order::SHIP
          row :shipping_name
          row :shipping_address do
            if order.shipping_info?
              div order.shipping_address_line1
              div order.shipping_address_line2
              div "#{order.shipping_city}, #{order.shipping_region} #{order.shipping_postal_code}"
              div order.shipping_country
            else
              'None'
            end
          end
          row 'Shipping Phone' do
            number_to_phone order.buyer_phone_number
          end
        end
      end
      if order.buyer_type == 'user'
        h5 link_to("View User in Admin", artsy_view_user_admin_url(order.buyer_id), class: :button)
      end

    end

    panel "Seller Information" do

      partner_info = GravityService.fetch_partner(order.seller_id)
      if partner_info.present?
        valid_partner_location = true
        begin
          partner_locations = GravityService.fetch_partner_locations(order.seller_id)
        rescue Errors::ValidationError
          valid_partner_location = false
        end

        if valid_partner_location
          #TODO - handle multiple partner_locations properly, instead of just taking the first.
          partner_location = partner_locations.first
          partner_info[:partner_location] = partner_location
          attributes_table_for partner_info do
            row :name
            row :partner_location do |partner_info|
              partner_location = partner_info[:partner_location]
              div partner_location.street_line1
              div partner_location.street_line2
              div "#{partner_location.city}, #{partner_location.region} #{partner_location.postal_code}"
            end
            row :email
          end
        else
          h3 "Failed to fetch partner location info"
        end
        h5 link_to("View Partner in Admin-Partners", artsy_view_partner_admin_url(order.seller_id), class: :button)
      else
        h3 "Failed to fetch partner info"
      end
    end
  end

  show do

    panel "Order Summary" do
      attributes_table_for order do
        row "Code" do |order|
          order.code
        end
        row "State" do |order|
          order.state
        end
        row 'Reason' do |order|
          order.state_reason
        end
        row 'Last Updated At' do |order|
          order.updated_at
        end

        last_admin_note = order.last_admin_note
        row 'Last admin action' do |order|
          if last_admin_note.present?
            last_admin_note.note_type.humanize
          end
        end
        row 'Last note' do |order|
          if last_admin_note.present?
            last_admin_note.description
          end
        end

        if order.state == Order::FULFILLED && order.fulfillment_type == Order::SHIP
          row 'Shipment' do |order|
            fulfillments = order.line_items.map(&:fulfillments).flatten
            table_for fulfillments do
              column '' do |fulfillment|
                attributes_table_for fulfillment do
                  row :courier
                  row :tracking_id
                  row :estimated_delivery
                end
              end
            end
          end
        end
      end
      br

      table_for order.state_histories do
        column 'Date', :created_at
        column :state
        column :reason
      end


    end

    panel "Transaction" do

      if order.credit_card_id.present?
        no_credit_card_found = false
        begin
          credit_card_info = GravityService.get_credit_card(order.credit_card_id)
          no_credit_card_found = !credit_card_info.present?
        rescue
          no_credit_card_found = true
        end
        if no_credit_card_found
          h5 "Paid #{number_to_currency(order.buyer_total_cents.to_f/100)} on #{pretty_format(order[:created_at])} (Failed to get credit card info)"
        else
          h5 "Paid #{number_to_currency(order.buyer_total_cents.to_f/100)} with #{credit_card_info[:brand]} ending in #{credit_card_info[:last_digits]} on #{pretty_format(order[:created_at])}"
        end
      end

      items_total = order.items_total_cents.to_f/100
      shipping_total = order.shipping_total_cents.to_f/100
      tax_total = order.tax_total_cents.to_f/100
      sub_total = items_total + shipping_total + tax_total

      transaction_fee = order.transaction_fee_cents.to_f/100
      commission_fee = order.commission_fee_cents.to_f/100
      seller_payout = sub_total - transaction_fee - commission_fee

      attributes_table_for order do
        row "Artwork Price" do |order|
          number_to_currency items_total
        end
        row "Shipping" do |order|
          number_to_currency shipping_total
        end
        row "Sales Tax" do |order|
          number_to_currency tax_total
        end
        row "Subtotal" do |order|
          number_to_currency(sub_total)
        end
        row "Processing Fee" do |order|
          number_to_currency(-transaction_fee, negative_format: "( %u%n )")
        end
        row "Artsy Fee" do |order|
          number_to_currency(-commission_fee, negative_format: "( %u%n )")
        end
        row "Seller Payout" do |order|
          number_to_currency(seller_payout)
        end

      end
    end

    panel "Admin Actions and Notes" do
      #TODO: Add "Add note" button
      h5 link_to("Add note", new_admin_order_admin_note_path(order), class: :button)
      table_for(order.admin_notes) do
        column :created_at
        column "Note Type" do |admin_note|
          admin_note.note_type.to_s.humanize
        end
        column :description
      end
    end
  end
end
