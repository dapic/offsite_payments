# encoding: utf-8
module OffsitePayments #:nodoc:
  module Integrations #:nodoc:
    module Alipay

      mattr_accessor :service_url
      self.service_url = 'https://mapi.alipay.com/gateway.do?_input_charset=utf-8'
      FIELDS_NOT_TO_BE_SIGNED = %w(sign sign_type)

      def self.notification(post, options = {})
        Notification.new(post, options)
      end

      def self.return(post, options = {})
        Return.new(post, options )
      end

      # Generate the required signature as specified in the "sign_type" field that's passed in in the "fields" argument
      # TODO: Only 'MD5' is supported at this point
      def self.generate_signature(fields, key)
        case sign_type = fields["sign_type"]
        when 'MD5'
          Digest::MD5.hexdigest(signed_string(fields, key))
        when nil
          raise OffsitePayments::ActionViewHelperError, "'sign_type' must be specified in the fields"
        else
          raise OffsitePayments::ActionViewHelperError, "sign_type '#{sign_type}' not yet supported"
        end
      end

      # Generate the string to sign on from the fields. Currently Alipay doc specifies that the fields are arranged alphabetically.
      def self.signed_string(fields, key)
          fields.reject do |s|
            FIELDS_NOT_TO_BE_SIGNED.include?(s)
          end
          .sort.collect do |s|
            s[0]+"="+CGI.unescape(s[1])
          end
          .join("&")+key
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
          @key = options.delete(:key) || "need key here"
          options.delete(:pid) #this should be passed in via the "account" argument
          #this :seller must be deleted from options, or it would fail the "assert_valid_keys" in "super" 
          seller = options.delete(:seller)
          super
          self.seller = seller 
        end

        def sign
          add_field('sign_type', 'MD5')
          add_field('sign', Alipay.generate_signature(@fields, @key))
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

      # contains functions to common to both "Notification" and "Return"
      module Common

        def is_payment_complete?
          # TRADE_SUCCESS is the success status for 开通了高级即时到账或机票分销产品后
          %w(TRADE_FINISHED TRADE_SUCCESS).include? trade_status
        end

        def status
          trade_status
        end

        # Verifies that the signature in the "sign" field is the same as would be generated with our "key"
        # Depends on the class has the @params and @key
        #   * @params the fields to be signed
        #   * @key the api key assigned by Alipay, corresponding to the "PID"
        def verify_signature
          #puts "sing in params: #{@params["sign"]}" unless @params["sign"] == Alipay.generate_signature(@params, @key)
          #puts Alipay.generate_signature(@params, @key)
          @params["sign"] == Alipay.generate_signature(@params, @key)
        end
        
        def acknowledge
          verify_signature || raise(ActionViewHelperError, "Invalid Alipay HTTP signature")
        end

        def has_all_required_fields?
          !self.class.const_defined?(:REQUIRED_FIELDS) || self.class::REQUIRED_FIELDS.all? {|f| params[f].present?}
        end
    
        # Parse the request query parameters into corresponding fields.
        # The key reason that the default Notification.parse() method is because, the "notify_id" field SHOULD NOT be unescaped first
        # There is no obvious documentation specifying this behavior, but the "return" URL generated by Alipay website calculates the
        # "sign" field based on the 'escaped' version of this field while other fields use the unescaped version
        def parse(post)
          @params ||= Hash.new
          @raw = post.to_s
          #puts ("-----parsing starts----") * 8
          for line in @raw.split('&')
            key, value = *line.scan( %r{^([A-Za-z0-9_.-]+)\=(.*)$} ).flatten
            if key.present?
              if self.class.const_defined?(:FIELDS_NOT_TO_BE_UNESCAPED_WHEN_PARSING) \
                && self.class::FIELDS_NOT_TO_BE_UNESCAPED_WHEN_PARSING.include?(key)
                params[key] = value.to_s
              else
                params[key] = CGI.unescape(value.to_s)
              end
            end
          end
          #puts ("-----parsing ends----") * 8
          @params
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

         #TODO: separate different fields for "Notification" and "Return" and put them into corresponding classes
         ['price', 'discount', 'quantity', 'total_fee', 'coupon_discount', 'logistics_fee'].each do |param|
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

         ['use_coupon', 'is_total_fee_adjust', 'is_success'].each do |param|
           self.class_eval <<-EOF
              def #{param}?
                'T' == params['#{param}']
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

      end

      class Notification < OffsitePayments::Notification
        include Common
        REQUIED_FIELDS = %w(notify_time notify_type notify_id sign_type sign)
        
        def initialize(post, options = {})
          super
          raise "Not valid Alipay #{self.class}" unless has_all_required_fields?
          @key = options[:key] || raise(RuntimeError, "key not provided to generate signature")
        end

        def pending?
          trade_status == 'WAIT_BUYER_PAY'
        end

        def gross
          @params['price']
        end

        def currency
          @params['currency'] || 'CNY'
        end
      end

      class Return < OffsitePayments::Return
        include Common
        REQUIRED_FIELDS =  %w(is_success sign_type sign)
        FIELDS_NOT_TO_BE_UNESCAPED_WHEN_PARSING = %w(notify_id)

        def initialize(post, options = {})
          super
          raise "Not valid Alipay #{self.class}" unless has_all_required_fields?
          @key = options[:key] || raise(RuntimeError, "key not provided to generate signature")
        end

        def order
          @params["out_trade_no"]
        end

        def amount
          @params["total_fee"]
        end

        def message
          @message
        end

        ['exterface'].each do |param|
          self.class_eval <<-EOF
              def #{param}
                params['#{param}']
              end
              EOF
        end
      end
    end
  end
end
