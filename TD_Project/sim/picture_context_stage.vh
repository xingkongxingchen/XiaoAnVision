
 // Only the eligibility condition is registered. The key router is reset
 // whenever normal_keys_enabled is low; its debounced release events cannot
 // occur until this condition has already settled. No command pulse is delayed.
 reg picture_key_context;
 always @(posedge sd_card_clk or negedge loader_rst_n)begin
  if(!loader_rst_n)picture_key_context<=0;
  else picture_key_context<=normal_keys_enabled;
 end
 