import { useState } from 'react';
import { v4 as uuidv4 } from 'uuid';

const FormDataManager = ({ children }) => {
  const id = uuidv4();
  const [formData, setFormData] = useState({
    id,
  });

  const updateFormData = (data: { id: any; }) => {
    setFormData((prevData) => ({
      ...prevData,
      ...data,
    }));
  };

  return children({ formData, updateFormData });
};

export default FormDataManager;
