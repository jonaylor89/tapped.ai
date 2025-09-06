'use client';

import React, { useState, useEffect } from 'react';
import { NextPage } from 'next';
import { useRouter } from 'next/navigation';
import FormDataManager from '@/components/FormDataManager';
import SegmentedLine from '@/components/SegmentedLine';
import { track } from '@vercel/analytics';
import NameField from '@/components/application/artist_name_field';
import FollowingField from '@/components/application/following_field';
import MarketingField from '@/components/application/marketing_field';
import AestheticField from '@/components/application/aesthetic_field';
import AudienceField from '@/components/application/audience_field';
import LeadingField from '@/components/application/leading_field';
import TimelineField from '@/components/application/timeline_field';
import BudgetField from '@/components/application/budget_field';
import SubmitField from '@/components/application/submit_field';
import ProductNameField from '@/components/application/product_name_field';

const paymentLink = process.env.NEXT_PUBLIC_STRIPE_PAYMENT_LINK;

const MarketingForm: NextPage = () => {
  if (!paymentLink) {
    return (
      <div className='h-screen flex flex-col justify-center items-center'>
        <div>whoa</div>
        <div>no payment link</div>
      </div>
    );
  }

  const [currentIndex, setCurrentIndex] = useState(0);
  const [isValid, setIsValid] = useState(false);
  const router = useRouter();
  const [formData, setFormData] = useState({});

  const defaultPages = [
    NameField,
    FollowingField,
    MarketingField,
    ProductNameField,
    AestheticField,
    AudienceField,
    TimelineField,
    BudgetField,
    SubmitField,
  ];

  const [pages, setPages] = useState(defaultPages);

  useEffect(() => {
    const updatedPages = [...defaultPages];
    if (formData['marketingType'] === 'single') {
      updatedPages.splice(3, 0, LeadingField);
    }
    setPages(updatedPages);
  }, [formData['marketingType']]);

  useEffect(() => {
    setIsValid(false);
  }, [currentIndex]);

  const handleNextPage = () => {
    if (isValid) {
      track('next-question', {
        index: currentIndex,
        question: pages[currentIndex].name,
      });
      setCurrentIndex((prev) => prev + 1);
    }
  };

  const handlePreviousPage = () => {
    if (currentIndex === 0) {
      router.push('/');
    } else {
      setCurrentIndex((prev) => prev - 1);
    }
  };

  if (pages.length <= 0) {
    return <h1>Form is empty</h1>;
  }

  const paymentFieldIndex = pages.indexOf(SubmitField);
  const backgroundColor = currentIndex === paymentFieldIndex ? '#15242d' : '#3ba0fc';

  return (
    <div className={'flex min-h-screen flex-col items-center justify-center px-4 md:px-8 lg:px-16'} style={{ backgroundColor: backgroundColor }}>
      <div className="w-full max-w-screen-md mx-auto">
        <SegmentedLine totalPages={pages.length} currentIndex={currentIndex} />
        <FormDataManager>
          {({ formData: formDataFromManager, updateFormData }) => {
            setFormData(formDataFromManager);
            const CurrentPage = pages[currentIndex];
            return (
              <>
                <CurrentPage
                  formData={formDataFromManager}
                  updateFormData={updateFormData}
                  onValidation={setIsValid}
                />
                <div className="flex justify-between mt-4 md:mt-8 lg:mt-16">
                  <button
                    className="tapped_btn_rounded"
                    onClick={handlePreviousPage}
                  >
                    back
                  </button>

                  {isValid && currentIndex !== pages.length - 1 && (
                    <button
                      className="tapped_btn_rounded_black"
                      onClick={handleNextPage}
                      disabled={!isValid}
                    >
                      next
                    </button>
                  )}
                </div>
              </>
            );
          }}
        </FormDataManager>
      </div>
    </div>
  );
};

export default MarketingForm;
