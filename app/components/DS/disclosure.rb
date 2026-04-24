class DS::Disclosure < DesignSystemComponent
  renders_one :summary_content

  attr_reader :title, :align, :open, :memo_key, :opts

  def initialize(title: nil, align: "right", open: false, memo_key: nil, **opts)
    @title = title
    @align = align.to_sym
    @open = open
    @memo_key = memo_key
    @opts = opts
  end
end
