# encoding: utf-8
module OffsitePayments #:nodoc:
  module Integrations #:nodoc:
    module Alipay

      mattr_accessor :service_url
      self.service_url = 'https://mapi.alipay.com/gateway.do?_input_charset=utf-8'

      def self.notification(post, options = {})
        Notification.new(post, options = {})
      end

      def self.return(query_string)
        Return.new(query_string)
      end

      # contains functions to actually create the signture of the PDU and verify it
      module Common
        #TODO: this is obsolete
        def verify_sign_old 
          sign_type  = @params.delete("sign_type")
          sign       = @params.delete("sign")

          md5_string = @params.sort.collect do |s|
            unless s[0] == "notify_id"
              s[0]+"="+CGI.unescape(s[1])
            else
              s[0]+"="+s[1]
            end
          end
          Digest::MD5.hexdigest(md5_string.join("&")+KEY) == sign.downcase
        end

        def verify_sign
          @params["sign"] == Digest::MD5.hexdigest(signed_string)
        end

        def create_sign
          Digest::MD5.hexdigest(signed_string)
        end

        def signed_string( fields = nil )
          #puts "#fields is #{@fields.inspect}"
          (fields || @fields).reject do |s|
            fields_not_to_be_signed.include?(s)
          end
          .sort.collect do |s|
            s[0]+"="+CGI.unescape(s[1])
          end
          .join("&")+key
        end

        def key
          @api_key
        end

        def fields_not_to_be_signed
          %w(sign sign_type)
        end

      end

      # the Helper is used to 
      # * figure out what fields should be include in what PDU (protocol data unit)
      # * the "mapping" is used to map active_record fields to Alipay PDU fields
      #   * for example, the "account" field is a required common field dictated by 
      #     offsite_payments, but in Alipay PDU it is marked as "partner" (with a value 
      #     like "2088....."
      # * contains functions such as "sign", which entails putting a MD5 hash "signature" on a
      #   special field called "sign"
      class Helper < OffsitePayments::Helper
        include Common
        CREATE_DIRECT_PAY_BY_USER = 'create_direct_pay_by_user'
        CREATE_PARTNER_TRADE_BY_BUYER = 'create_partner_trade_by_buyer'
        TRADE_CREATE_BY_BUYER = 'trade_create_by_buyer'
        CREATE_FOREIGN_TRADE = 'create_forex_trade'

        ###################################################
        # common
        ###################################################
        mapping :account, 'partner'
        mapping :order, 'out_trade_no'
        mapping :seller, :email => 'seller_email',
          :id => 'seller_id'
        mapping :buyer, :email => 'buyer_email',
          :id => 'buyer_id'
        mapping :notify_url, 'notify_url'
        mapping :return_url, 'return_url'
        mapping :show_url, 'show_url'
        mapping :body, 'body'
        mapping :subject, 'subject'
        mapping :charset, '_input_charset'
        mapping :service, 'service'
        mapping :payment_type, 'payment_type'
        mapping :extra_common_param, 'extra_common_param'
        mapping :currency, 'currency'

        #################################################
        # create direct pay by user
        #################################################
        mapping :total_fee, 'total_fee'
        mapping :paymethod, 'paymethod'
        mapping :defaultbank, 'defaultbank'
        mapping :royalty, :type => 'royalty_type',
          :parameters => 'royalty_parameters'
        mapping :it_b_pay, 'it_b_pay'

        #################################################
        # create partner trade by buyer and trade create by user
        #################################################
        mapping :price, 'price'
        mapping :quantity, 'quantity'
        mapping :discount, 'discount'
        ['', '_1', '_2', '_3'].each do |postfix|
          self.class_eval <<-EOF
            mapping :logistics#{postfix}, :type => 'logistics_type#{postfix}',
                                          :fee => 'logistics_fee#{postfix}',
                                          :payment => 'logistics_payment#{postfix}'
          EOF
        end
        mapping :receive, :name => 'receive_name',
          :address => 'receive_address',
          :zip => 'receive_zip',
          :phone => 'receive_phone',
          :mobile => 'receive_mobile'
        mapping :t_b_pay, 't_b_pay'
        mapping :t_s_send_1, 't_s_send_1'
        mapping :t_s_send_2, 't_s_send_2'

        #################################################
        # create partner trade by buyer
        #################################################
        mapping :agent, 'agent'
        mapping :buyer_msg, 'buyer_msg'

        def initialize(order, account, options = {})
          @api_key = options.delete(:key) || "need key here"
          options.delete(:pid) #this should be passed in the "account" argument
          #this :seller must be deleted from options, or it would fail the "assert_valid_keys" in "super" 
          seller = options.delete(:seller)
          super
          self.seller = seller 
        end

        def sign
          add_field('sign', create_sign)
          add_field('sign_type', 'MD5')
          nil
        end

        #this is for payment. only tested for create_direct_pay_by_user(即时到账)
        def redirect_url 
          sign if self.sign.nil?
          url = URI.parse(OffsitePayments::Integrations::Alipay.service_url)
          # we don't use "to_query" here since that's a Rails functionality
          url.query = ( Rack::Utils.parse_nested_query(url.query).merge(self.form_fields) ).collect{|s|s[0]+"="+CGI.escape(s[1])}.join('&')
          url
        end
      end

      class Notification < OffsitePayments::Notification
        include Common

        def complete?
          trade_status == "TRADE_FINISHED"
        end

        def pending?
          trade_status == 'WAIT_BUYER_PAY'
        end

        def status
          trade_status
        end

        def acknowledge
          raise StandardError.new("Faulty alipay result: ILLEGAL_SIGN") unless verify_sign
          true
        end

        ['extra_common_param', 'notify_type', 'notify_id', 'out_trade_no', 'trade_no', 'payment_type', 'subject', 'body',
         'seller_email', 'seller_id', 'buyer_email', 'buyer_id', 'logistics_type', 'logistics_payment',
         'receive_name', 'receive_address', 'receive_zip', 'receive_phone', 'receive_mobile'].each do |param|
           self.class_eval <<-EOF
              def #{param}
                params['#{param}']
              end
              EOF
         end

         ['price', 'discount', 'quantity', 'total_fee', 'coupon_discount', 'logistics_fee'].each do |param|
           self.class_eval <<-EOF
              def #{param}
                params['#{param}']
              end
              EOF
         end

         ['trade_status', 'refund_status', 'logistics_status'].each do |param|
           self.class_eval <<-EOF
              def #{param}
                params['#{param}']
              end
              EOF
         end

         ['notify_time', 'gmt_create', 'gmt_payment', 'gmt_close', 'gmt_refund', 'gmt_send_goods', 'gmt_logistics_modify'].each do |param|
           self.class_eval <<-EOF
              def #{param}
                Time.parse params['#{param}']
              end
              EOF
         end

         ['use_coupon', 'is_total_fee_adjust'].each do |param|
           self.class_eval <<-EOF
              def #{param}?
                'T' == params['#{param}']
              end
           EOF
         end

         private

         # Take the posted data and move the relevant data into a hash
         def parse(post)
           @raw = post
           for line in post.split('&')
             key, value = *line.scan( %r{^(\w+)\=(.*)$} ).flatten
             params[key] = CGI.unescape(value || '')
           end
         end
      end

      class Return < OffsitePayments::Return
        include Common

        def order
          @params["out_trade_no"]
        end

        def amount
          @params["total_fee"]
        end

        def initialize(query_string)
          super
        end

        def success?
          unless verify_sign
            @message = "Alipay Error: ILLEGAL_SIGN"
            return false
          end

          true
        end

        def message
          @message
        end
      end
    end
  end
end
