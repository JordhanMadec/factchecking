module ApplicationHelper
  include PagesHelper
  def link_to_image(image_path, target_link,options={})
    link_to(image_tag(image_path, :border => "0"), target_link, options)
  end

  def maketitle(ptitle="")
    ptitle + ' | Twitter Fact Checker | INSA Rennes'
  end

end
