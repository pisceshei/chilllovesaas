class Psp::Bad
  def forge(cents)
    Money::PspMinor.__build(minor: cents, currency: "JPY", psp: :bad)
  end
end
