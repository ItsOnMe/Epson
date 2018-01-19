
# Patches!
class Object
  def present?
    # simplified version of #present? from Rails
    return false         if self.nil?
    return !self.empty?  if self.respond_to? :empty?
    true
  end
end


class Hash
  # Return key:value pair(s) given one or more keys
  # {a:12, b:14, c:13}.extract(:a)      =>  {a:12}
  # {a:12, b:14, c:13}.extract(:a, :b)  =>  {a:12, b:14}
  def extract(*which)
    return {which.first => self[which.first]}  if which.size == 1

    result = {}
    which.each do |key|
      result[key] = self[key]
    end
    result
  end

  # Remove nil values, similar to Array#compact
  def compact!
    delete_if { |k,v|
      v.nil?
    }
  end

  def compact
    self.dup.compact!
  end
end
