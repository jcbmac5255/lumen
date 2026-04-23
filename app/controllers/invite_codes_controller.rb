class InviteCodesController < ApplicationController
  before_action :ensure_self_hosted

  def index
    @invite_codes = InviteCode.all
  end

  def create
    raise StandardError, "You are not allowed to generate invite codes" unless Current.user.admin?
    @invite_code = InviteCode.create!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.append("invite_codes_list", partial: "invite_codes/invite_code", locals: { invite_code: @invite_code }) }
      format.html { redirect_back_or_to invite_codes_path, notice: "Code generated" }
    end
  end

  def destroy
    raise StandardError, "You are not allowed to delete invite codes" unless Current.user.admin?
    invite_code = InviteCode.find(params[:id])
    invite_code.destroy!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(helpers.dom_id(invite_code)) }
      format.html { redirect_back_or_to invite_codes_path, notice: "Code deleted" }
    end
  end

  private

    def ensure_self_hosted
      redirect_to root_path unless self_hosted?
    end
end
