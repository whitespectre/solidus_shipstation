# frozen_string_literal: true

require 'spec_helper'

describe Spree::ShipstationController do
  render_views
  routes { Spree::Core::Engine.routes }
  let(:auth_params) do
    {
      SolidusShipstation.config.username_param => SolidusShipstation.config.username,
      SolidusShipstation.config.password_param => SolidusShipstation.config.password
    }
  end

  before do
    allow(described_class).to receive(:spree_current_user).and_return(FactoryBot.create(:user))
    @request.env['HTTP_ACCEPT'] = 'application/xml'
  end

  context 'logged in' do
    describe '#export' do
      let(:schema) { 'spec/fixtures/shipstation_xml_schema.xsd' }
      let(:order) { create(:order, state: 'complete', completed_at: Time.now.utc) }
      let!(:shipments) { create(:shipment, state: 'ready', order: order) }
      let(:params) do
        {
          start_date: 1.day.ago.strftime('%m/%d/%Y %H:%M'),
          end_date: 1.day.from_now.strftime('%m/%d/%Y %H:%M'),
          format: 'xml'
        }.merge!(auth_params)
      end

      before { get :export, params: params }

      it 'renders successfully', :aggregate_failures do
        expect(response.status).to eq(200)
        expect(response).to render_template(:export)
        expect(assigns(:shipments)).to match_array([shipments])
      end

      it 'generates valid ShipStation formatted xml' do
        expect(response.body).to pass_validation(schema)
      end
    end

    describe '#shipnotify' do
      # NOTE: Spree::Shipment factory creates new instances with tracking numbers,
      #   which might not reflect reality in practice
      let(:order_number) { 'ABC123' }
      let(:tracking_number) { '123456' }
      let(:order) { create(:order, payment_state: 'paid') }
      let!(:shipment) do
        shipment = create(:shipment, tracking: nil, number: order_number, order: order)
        shipment.address_id = order.ship_address.id if shipment.has_attribute?(:address_id)
        shipment.save
        shipment
      end
      let!(:inventory_unit) { create(:inventory_unit, order: order, shipment: shipment) }

      context 'shipment found' do
        let(:params) do
          { order_number: order_number, tracking_number: tracking_number }.merge!(auth_params)
        end

        before do
          allow(order).to receive(:can_ship?).and_return(true)
          allow(order).to receive(:paid?).and_return(true)
          shipment.ready!

          post :shipnotify, params: params
        end

        it 'updates the shipment', :aggregate_failures do
          expect(shipment.reload.tracking).to eq(tracking_number)
          expect(shipment.state).to eq('shipped')
          expect(shipment.shipped_at).to be_present
        end

        it 'responds with success' do
          expect(response.status).to eq(200)
        end
      end

      context 'shipment not found' do
        let(:invalid_params) do
          { order_number: 'JJ123456' }.merge!(auth_params)
        end

        before { post :shipnotify, params: invalid_params }

        it 'responds with failure' do
          expect(response.status).to eq(400)
        end
      end
    end
  end

  context 'not logged in' do
    it 'returns error' do
      get :export, params: { format: 'xml' }

      expect(response.status).to eq(401)
    end
  end
end
