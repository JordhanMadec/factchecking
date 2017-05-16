module ApplicationHelper
  include PagesHelper
  def link_to_image(image_path, target_link,options={})
    link_to(image_tag(image_path, :border => "0"), target_link, options)
  end

  def make_title(title='')
    title + ' | Twitter Fact Checker | INSA Rennes'
  end

  def get_path_for_search
    if current_page?(root_url)
      'pages/result'
    else
      'result'
    end
  end

end
