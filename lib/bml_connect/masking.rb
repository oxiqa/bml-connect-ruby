# frozen_string_literal: true

module BMLConnect
  # Detects and redacts card-number-like data. This library never has a
  # legitimate reason to carry a PAN, so any value that looks like one is
  # rejected on input and scrubbed from any log output.
  #
  # Ported from the retired bml_tokenization gem, whose masking was the one
  # part of its engineering that was sound.
  module Masking
    # 13–19 digits, allowing a single space or dash between digits (the common
    # ways a PAN gets pasted). Deliberately broad; the Luhn check below removes
    # the false positives a bare length match would produce.
    PAN_PATTERN = /\d(?:[ -]?\d){12,18}/.freeze

    REDACTION = "[FILTERED]"

    module_function

    # True when +value+ contains a substring that both matches the PAN shape
    # and passes the Luhn checksum. The Luhn gate keeps ordinary long numbers
    # (tax ids, references) from being misread as card numbers.
    def looks_like_pan?(value)
      return false unless value.is_a?(String)

      value.scan(PAN_PATTERN).any? { |candidate| luhn_valid?(candidate.gsub(/[ -]/, "")) }
    end

    # Standard Luhn (mod-10) validation over a digit string.
    def luhn_valid?(digits)
      return false unless digits.length.between?(13, 19)

      sum = 0
      digits.reverse.each_char.each_with_index do |char, index|
        n = char.to_i
        if index.odd?
          n *= 2
          n -= 9 if n > 9
        end
        sum += n
      end
      (sum % 10).zero?
    end

    # Replace any PAN-like substring in +text+ with the redaction marker.
    # Used to guarantee no card data survives into a log line.
    def scrub(text)
      return text unless text.is_a?(String)

      text.gsub(PAN_PATTERN) do |candidate|
        luhn_valid?(candidate.gsub(/[ -]/, "")) ? REDACTION : candidate
      end
    end
  end
end
