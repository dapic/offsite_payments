# encoding: utf-8
module OffsitePayments #:nodoc:
  module Integrations #:nodoc:
    module AlipayWap

      mattr_accessor :service_url, :logger, :credentials
      @@service_url = 'http://wappaygw.alipay.com/service/rest.htm'

      def self.logger
        @@logger ||= (require 'logger'; Logger.new(STDOUT))
      end

      module Common
        def request_fields
          @protocol_fields.merge({'req_data' => payload_xml(@payload_fields)})
        end

        def assemble_post_params(param_fields)
          param_fields.collect { |s| "#{s[0]}=#{CGI.escape(s[1])}" }.join('&')
        end

      end

      module CredentialHelper
        def key;
          AlipayWap.credentials[:key];
        end

        def partner;
          AlipayWap.credentials[:pid].to_s;
        end

        def seller_email;
          AlipayWap.credentials[:seller][:email];
        end
      end

      module SignatureProcessor
        FIELDS_NOT_TO_BE_SIGNED = 'sign'

        def sign
          @protocol_fields['sign'] ||= generate_signature
        end

        def generate_signature
          case sign_type = @protocol_fields['sec_id']
            when 'MD5'
              Digest::MD5.hexdigest(signed_string)
            when '0001' #RSA
              raise OffsitePayments::ActionViewHelperError, "sign_type '0001' -> RSA not yet supported"
            when nil
              raise OffsitePayments::ActionViewHelperError, "'sign_type' must be specified in the fields"
            else
              raise OffsitePayments::ActionViewHelperError, "sign_type '#{sign_type}' not yet supported"
          end
        end

        # Generate the string to sign on from all in @request_fields.
        # Currently Alipay doc specifies that the fields are arranged alphabetically except for data sent to "notify_url"
        def signed_string(sort_first = true)
          signed_data_only = request_fields.reject { |s| FIELDS_NOT_TO_BE_SIGNED.include?(s) }
          assemble_post_params(sort_first ? signed_data_only.sort : signed_data_only) + key
        end

        def acknowledge
          (request_fields['sign'] == generate_signature) || raise(SecurityError, "Invalid Alipay HTTP signature in #{self.class}")
        end
      end

      #depends on the "payload" method
      module OutgoingRequestProcessor
        def process
          @post_response = ssl_post(AlipayWap.service_url, payload)
          @response = parse_response
        end

        def parse_response
          case self.class
            when CreateDirectHelper
              CreateDirectResponse.new(@post_response, self)
            else
              raise "response class for #{self.class.name} not defined/implemented yet"
          end
        end

      end

      class CreateDirectHelper #< OffsitePayments::Helper
        include Common
        include CredentialHelper
        include SignatureProcessor
        include OutgoingRequestProcessor
        attr_accessor :protocol_fields, :payload_fields

        PROTOCOL_STATIC_FIELDS = {
            '_input_charset' => 'utf-8',
            'service' => 'alipay.wap.trade.create.direct',
            'format' => 'xml',
            'v' => '2.0',
            'sec_id' => 'MD5',
        }

        def initialize(biz_data)
          @payload_fields = biz_data.merge(seller_account_name: seller_email)
          @protocol_fields = PROTOCOL_STATIC_FIELDS.merge({
                                                              'partner' => partner,
                                                              'req_id' => SecureRandom.hex(16).to_s,
                                                          })
          #@fields = @protocol_fields.merge {'req_data' => payload_xml(@biz_data)}
          sign
        end

        def payload
          assemble_post_params(request_fields.sort)
        end

        def payload_xml(biz_data)
          xml = biz_data.map { |k, v| "<#{k}>#{v.encode(:xml => :text)}</#{k}>" }.join
          "<direct_trade_create_req>#{xml}</direct_trade_create_req>"
        end

      end

      class CreateDirectResponse
        require 'nokogiri'
        include SignatureProcessor
        attr_reader :request_token, :error
        # ignore_signature_check should be used in testing only!
        def initialize(raw_response, req, ignore_signature_check = false)
          @raw_response, @request = raw_response, req
          parse ignore_signature_check
        end

        def parse(ignore_signature_check)
          raise TypeError unless @raw_response.is_a? String
          @protocol_fields = @raw_response.split('&').inject({}) { |h, kv| k, v = kv.split('=', 2); h[k] = v; h }
          credential_check

          case
            when @protocol_fields.has_key?('res_data')
              acknowledge unless ignore_signature_check
              @request_token = Nokogiri::XML(@protocol_fields.delete('res_data')).at_xpath('//request_token').content
            when @protocol_fields.has_key?('res_error')
              @error = Nokogiri::XML(@protocol_fields.delete('res_error')).xpath('//err').children.inject({}) do |h, node|
                h[node.name] = node.content.strip; h
              end
            else
              raise "Invalid response format for #{self.class}"
          end
        end

        # verify if this response is for this request
        def credential_check
          %w(partner req_id service v).all? { |k|
            # AlipayWap.logger.debug "#{k}: #{@protocol_fields[k]}<->#{@request.protocol_fields[k]}"
            @protocol_fields[k] == @request.protocol_fields[k].to_s
          } || raise("Response is not for this request")
        end
      end

      class AuthAndExecuteHelper # < OffsitePayments::Helper
        include Common
        include CredentialHelper
        include SignatureProcessor
      end

    end #
  end
end
